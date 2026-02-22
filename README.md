# AWS GitOps Toolbox

Herramientas, plantillas y pipelines para implementar infraestructura AWS usando GitOps, con enfoque en ECS, Application Load Balancers y CI/CD.

## 📋 Contenido

Este repositorio contiene:
- **CloudFormation Templates** para crear clusters ECS, ALBs y servicios
- **Task Definitions** para contenedores (Nginx con puertos 80, 8080, 443)
- **GitHub Actions** workflow para despliegue automático
- **Jenkinsfile** para integración con GitLab mediante webhooks
- **Scripts** de utilidad para despliegue manual

## 🏗️ Arquitectura

```
Internet
    │
    ▼
┌─────────────────────────┐
│  Application Load       │
│     Balancer (ALB)      │
│  Ports: 80, 443, 8080   │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│    Target Groups        │
│  - TG-80 (port 80)      │
│  - TG-8080 (port 8080)  │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│     ECS Service         │
│   (Fargate Tasks)       │
└─────────────────────────┘
    │
    ▼
┌─────────────────────────┐
│    ECS Cluster          │
│  Container Insights     │
└─────────────────────────┘
```

## 🚀 Quick Start

### Prerrequisitos

1. **AWS CLI** configurado con credenciales válidas
2. **Permisos AWS** para ECS, ELB, CloudFormation, IAM
3. **Git** configurado con acceso al repositorio
4. Para GitHub Actions: Secrets configurados en el repositorio
5. Para Jenkins: Plugin de GitLab y credenciales AWS configuradas

### Configuración de Secrets (GitHub)

En tu repositorio de GitHub, ve a Settings → Secrets and variables → Actions y agrega:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### Configuración de Jenkins

1. Instalar plugins requeridos:
   - GitLab Plugin
   - AWS Credentials Plugin
   - Docker Pipeline Plugin

2. Configurar credenciales AWS en Jenkins con ID: `aws-credentials-id`

3. Configurar webhook en GitLab:
   - URL: `http://tu-jenkins:8080/project/aws-gitops-toolbox`
   - Secret Token: Configurar en Jenkins y GitLab
   - Eventos: Push events, Merge request events

## 📁 Estructura del Repositorio

```
aws-gitops-toolbox/
├── clusters/
│   └── ecs-cluster.json          # Definición del cluster ECS
├── loadbalancers/
│   └── nginx-alb.json            # ALB con listeners para 80, 443, 8080
├── services/
│   └── nginx-service.json        # Servicio ECS con auto-scaling
├── task-definitions/
│   └── nginx-task.json           # Task definition para Nginx
├── pipelines/
│   ├── github-actions/
│   │   └── deploy-aws.yml        # GitHub Actions workflow
│   └── jenkins/
│       └── Jenkinsfile           # Pipeline para Jenkins
├── scripts/
│   └── deploy.sh                 # Script de despliegue manual
└── README.md
```

## 🔧 Uso

### Opción 1: Despliegue Automático con GitHub Actions

El despliegue se ejecuta automáticamente cuando:
- Se hace push a la rama `main`
- Se acepta un Pull Request hacia `main`

### Opción 2: Despliegue con Jenkins + GitLab

1. Configura el webhook en GitLab apuntando a tu Jenkins
2. El pipeline se ejecuta automáticamente al hacer push a `main`
3. Jenkins usa la imagen oficial de AWS CLI para los despliegues

### Opción 3: Despliegue Manual

```bash
# Clonar el repositorio
git clone https://github.com/tu-usuario/aws-gitops-toolbox.git
cd aws-gitops-toolbox

# Ejecutar script de despliegue
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## 📝 Personalización

### Modificar puertos

Los puertos están definidos en:
- `loadbalancers/nginx-alb.json`: Listeners del ALB
- `task-definitions/nginx-task.json`: Port mappings del contenedor
- `services/nginx-service.json`: Security groups del servicio

### Cambiar la imagen del contenedor

Edita `task-definitions/nginx-task.json`:
```json
"image": "tu-registro/tu-imagen:tag"
```

### Ajustar recursos

En `task-definitions/nginx-task.json`:
```json
"cpu": "512",      # 0.5 vCPU
"memory": "1024"   # 1 GB RAM
```

### Configurar Auto Scaling

En `services/nginx-service.json`, ajusta los parámetros:
```json
"DesiredCount": 2,
"MinCapacity": 1,
"MaxCapacity": 4
```

## 🔍 Monitoreo

### CloudWatch Container Insights

Habilitado por defecto en el cluster. Accede a métricas en:
- AWS Console → CloudWatch → Container Insights

### Logs

Los logs se envían a CloudWatch Logs:
- Log Group: `/ecs/nginx`
- Stream prefix: `nginx`

### Health Checks

- ALB health check: `/health` en puerto 80
- API health check: `/api/health` en puerto 8080
- Container health check: curl interno cada 30 segundos

## 🛠️ Solución de Problemas

### El stack de CloudFormation falla

```bash
# Ver eventos del stack
aws cloudformation describe-stack-events \
  --stack-name nombre-del-stack \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### El servicio ECS no inicia

```bash
# Ver estado del servicio
aws ecs describe-services \
  --cluster nginx-production-cluster \
  --services nginx-service

# Ver logs de las tareas
aws logs tail /ecs/nginx --follow
```

### El ALB no responde

1. Verificar Security Groups
2. Confirmar que los Target Groups tienen targets healthy
3. Revisar los logs del contenedor

## 📊 Costos Estimados (us-east-1)

- **ECS Fargate**: ~$0.04/hora por tarea (0.5 vCPU, 1GB RAM)
- **Application Load Balancer**: ~$0.025/hora + $0.008/LCU
- **CloudWatch Logs**: ~$0.50/GB ingesta
- **Total mensual estimado**: ~$50-100 (2 tareas, tráfico moderado)

## 🔒 Seguridad

- Los Security Groups están configurados con el principio de menor privilegio
- El contenedor Nginx corre con usuario no-root
- Las capacidades de Linux están limitadas
- El tráfico entre ALB y ECS está restringido por Security Groups
- EFS en tránsito está encriptado

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:
1. Fork el repositorio
2. Crea una rama para tu feature
3. Haz commit de tus cambios
4. Push a la rama
5. Abre un Pull Request

## 📄 Licencia

MIT License - ver archivo [LICENSE](LICENSE)

## 🔗 Enlaces Útiles

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [CloudFormation Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CLI Docker Image](https://gallery.ecr.aws/aws-cli/aws-cli)
- [GitHub Actions AWS](https://github.com/aws-actions)

## 📞 Soporte

Para preguntas o problemas, abre un issue en el repositorio.