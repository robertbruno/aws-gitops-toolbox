#!/bin/bash

# AWS GitOps Toolbox - Manual Deployment Script
# Este script despliega la infraestructura AWS sin necesidad de CI/CD

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuración
AWS_REGION=${AWS_REGION:-"us-east-1"}
CLUSTER_STACK=${CLUSTER_STACK:-"ecs-cluster-stack"}
ALB_STACK=${ALB_STACK:-"alb-stack"}
SERVICE_STACK=${SERVICE_STACK:-"nginx-service-stack"}

# Función para imprimir mensajes con color
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar que AWS CLI está instalado
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI no está instalado. Por favor, instálalo primero."
        exit 1
    fi
    print_info "AWS CLI encontrado: $(aws --version)"
}

# Verificar credenciales AWS
check_aws_credentials() {
    print_info "Verificando credenciales AWS..."
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "No se pudieron validar las credenciales AWS."
        print_error "Configura tus credenciales con: aws configure"
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_info "Cuenta AWS: $ACCOUNT_ID"
    print_info "Región: $AWS_REGION"
}

# Validar templates de CloudFormation
validate_templates() {
    print_info "Validando templates de CloudFormation..."

    # Validar cluster template
    if aws cloudformation validate-template \
        --template-body file://clusters/ecs-cluster.json \
        --region $AWS_REGION &> /dev/null; then
        print_info "✓ Template de cluster válido"
    else
        print_error "✗ Template de cluster inválido"
        exit 1
    fi

    # Validar ALB template
    if aws cloudformation validate-template \
        --template-body file://loadbalancers/nginx-alb.json \
        --region $AWS_REGION &> /dev/null; then
        print_info "✓ Template de ALB válido"
    else
        print_error "✗ Template de ALB inválido"
        exit 1
    fi

    # Validar service template
    if aws cloudformation validate-template \
        --template-body file://services/nginx-service.json \
        --region $AWS_REGION &> /dev/null; then
        print_info "✓ Template de servicio válido"
    else
        print_error "✗ Template de servicio inválido"
        exit 1
    fi
}

# Obtener información de red
get_network_info() {
    print_info "Obteniendo información de red..."

    # Obtener VPC por defecto
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" \
        --output text \
        --region $AWS_REGION)

    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        print_error "No se encontró VPC por defecto. Creando una..."
        # Aquí podrías agregar lógica para crear una VPC
        exit 1
    fi

    print_info "VPC ID: $VPC_ID"

    # Obtener subnets públicas
    PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
        --query "Subnets[0:2].SubnetId" \
        --output text \
        --region $AWS_REGION | tr '\t' ',')

    if [ -z "$PUBLIC_SUBNETS" ]; then
        print_error "No se encontraron subnets públicas"
        exit 1
    fi

    print_info "Subnets públicas: $PUBLIC_SUBNETS"

    # Obtener subnets privadas (si no hay, usar las públicas)
    PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=false" \
        --query "Subnets[0:2].SubnetId" \
        --output text \
        --region $AWS_REGION | tr '\t' ',')

    if [ -z "$PRIVATE_SUBNETS" ]; then
        print_warning "No se encontraron subnets privadas, usando las públicas"
        PRIVATE_SUBNETS=$PUBLIC_SUBNETS
    else
        print_info "Subnets privadas: $PRIVATE_SUBNETS"
    fi
}

# Desplegar ECS Cluster
deploy_cluster() {
    print_info "Desplegando ECS Cluster..."

    aws cloudformation deploy \
        --stack-name $CLUSTER_STACK \
        --template-file clusters/ecs-cluster.json \
        --parameter-overrides \
            ClusterName=nginx-production-cluster \
            EnableContainerInsights=enabled \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-fail-on-empty-changeset \
        --region $AWS_REGION \
        --tags Environment=Production ManagedBy=Manual

    print_info "✓ Cluster desplegado exitosamente"
}

# Desplegar Application Load Balancer
deploy_alb() {
    print_info "Desplegando Application Load Balancer..."

    aws cloudformation deploy \
        --stack-name $ALB_STACK \
        --template-file loadbalancers/nginx-alb.json \
        --parameter-overrides \
            VpcId=$VPC_ID \
            PublicSubnets=$PUBLIC_SUBNETS \
            CertificateArn="" \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-fail-on-empty-changeset \
        --region $AWS_REGION \
        --tags Environment=Production ManagedBy=Manual

    print_info "✓ ALB desplegado exitosamente"
}

# Registrar Task Definition
register_task_definition() {
    print_info "Registrando Task Definition..."

    # Crear directorio temporal
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE="$TEMP_DIR/nginx-task-resolved.json"

    # Reemplazar placeholders
    sed -e "s/\${AWS_ACCOUNT_ID}/$ACCOUNT_ID/g" \
        -e "s/\${AWS_REGION}/$AWS_REGION/g" \
        -e "s/\${EFS_ID}/fs-12345678/g" \
        -e "s/\${EFS_ACCESS_POINT_CONFIG}/fsap-config123/g" \
        -e "s/\${EFS_ACCESS_POINT_HTML}/fsap-html456/g" \
        task-definitions/nginx-task.json > $TEMP_FILE

    # Registrar task definition
    TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file://$TEMP_FILE \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text \
        --region $AWS_REGION)

    # Limpiar archivos temporales
    rm -rf $TEMP_DIR

    print_info "✓ Task Definition registrada: $TASK_DEF_ARN"
}

# Desplegar ECS Service
deploy_service() {
    print_info "Desplegando ECS Service..."

    aws cloudformation deploy \
        --stack-name $SERVICE_STACK \
        --template-file services/nginx-service.json \
        --parameter-overrides \
            ClusterStackName=$CLUSTER_STACK \
            ALBStackName=$ALB_STACK \
            VpcId=$VPC_ID \
            PrivateSubnets=$PRIVATE_SUBNETS \
            TaskDefinitionArn=$TASK_DEF_ARN \
            DesiredCount=2 \
            MinCapacity=1 \
            MaxCapacity=4 \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-fail-on-empty-changeset \
        --region $AWS_REGION \
        --tags Environment=Production ManagedBy=Manual

    print_info "✓ Servicio desplegado exitosamente"
}

# Obtener URL del Load Balancer
get_alb_url() {
    print_info "Obteniendo URL del Application Load Balancer..."

    ALB_DNS=$(aws cloudformation describe-stacks \
        --stack-name $ALB_STACK \
        --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDNS'].OutputValue" \
        --output text \
        --region $AWS_REGION)

    if [ ! -z "$ALB_DNS" ]; then
        echo ""
        echo "=========================================="
        echo -e "${GREEN}🚀 Despliegue completado exitosamente!${NC}"
        echo "=========================================="
        echo -e "${GREEN}📡 Aplicación disponible en:${NC}"
        echo -e "  - HTTP: ${YELLOW}http://$ALB_DNS${NC}"
        echo -e "  - Puerto alternativo: ${YELLOW}http://$ALB_DNS:8080${NC}"
        echo -e "  - HTTPS: ${YELLOW}https://$ALB_DNS${NC} (requiere certificado)"
        echo "=========================================="
        echo ""
    else
        print_warning "No se pudo obtener la URL del ALB"
    fi
}

# Función para esperar que el servicio esté estable
wait_for_service() {
    print_info "Esperando que el servicio se estabilice..."

    aws ecs wait services-stable \
        --cluster nginx-production-cluster \
        --services nginx-service \
        --region $AWS_REGION 2>/dev/null || {
        print_warning "El servicio tardó más de lo esperado en estabilizarse"
    }
}

# Función para rollback en caso de error
rollback() {
    print_error "Ocurrió un error. Iniciando rollback..."

    # Intentar cancelar actualización del stack de servicio
    aws cloudformation cancel-update-stack \
        --stack-name $SERVICE_STACK \
        --region $AWS_REGION 2>/dev/null || true

    print_info "Rollback iniciado"
}

# Función principal
main() {
    echo "=========================================="
    echo "   AWS GitOps Toolbox - Deploy Script"
    echo "=========================================="
    echo ""

    # Configurar trap para rollback en caso de error
    trap rollback ERR

    # Verificaciones iniciales
    check_aws_cli
    check_aws_credentials
    validate_templates

    # Obtener información de red
    get_network_info

    # Preguntar confirmación
    echo ""
    read -p "¿Deseas continuar con el despliegue? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Despliegue cancelado por el usuario"
        exit 0
    fi

    # Desplegar infraestructura
    deploy_cluster
    deploy_alb
    register_task_definition
    deploy_service

    # Esperar y obtener URL
    wait_for_service
    get_alb_url

    print_info "¡Despliegue completado!"
}

# Manejo de argumentos
case "${1:-}" in
    --help|-h)
        echo "Uso: $0 [opciones]"
        echo ""
        echo "Opciones:"
        echo "  --help, -h         Mostrar esta ayuda"
        echo "  --validate         Solo validar templates sin desplegar"
        echo "  --destroy          Eliminar todos los stacks"
        echo ""
        echo "Variables de entorno:"
        echo "  AWS_REGION         Región AWS (default: us-east-1)"
        echo "  CLUSTER_STACK      Nombre del stack del cluster"
        echo "  ALB_STACK          Nombre del stack del ALB"
        echo "  SERVICE_STACK      Nombre del stack del servicio"
        exit 0
        ;;
    --validate)
        check_aws_cli
        check_aws_credentials
        validate_templates
        print_info "Todos los templates son válidos"
        exit 0
        ;;
    --destroy)
        print_warning "Eliminando stacks..."
        aws cloudformation delete-stack --stack-name $SERVICE_STACK --region $AWS_REGION 2>/dev/null || true
        aws cloudformation delete-stack --stack-name $ALB_STACK --region $AWS_REGION 2>/dev/null || true
        aws cloudformation delete-stack --stack-name $CLUSTER_STACK --region $AWS_REGION 2>/dev/null || true
        print_info "Stacks marcados para eliminación"
        exit 0
        ;;
    *)
        main
        ;;
esac