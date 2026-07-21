# Rol IAM de despliegue

`infrastructure/deployment-role.yml` es una plantilla bootstrap separada. Debe ejecutarla una sola vez un administrador de la cuenta, indicando como `TrustedPrincipalArn` el usuario o rol autorizado para asumirla.

El rol resultante se llama `epico-deployment-production`, dura como máximo cuatro horas y restringe recursos regionales a `us-east-1` y nombres `epico`/`ms-epico` cuando AWS admite permisos por ARN. Las APIs globales o de creación que no soportan esa restricción se enumeran explícitamente con `Resource: '*'`.

## Validación sin despliegue

```powershell
./scripts/validate-deployment-role.ps1
```

## Bootstrap futuro

1. Copiar `deployment-role-parameters.example.json` como `deployment-role-parameters.json`.
2. Completar `TrustedPrincipalArn` y `CostCenterTag`.
3. Desplegar la plantilla con un principal bootstrap autorizado y `CAPABILITY_NAMED_IAM`.
4. Conservar el Output `DeploymentRoleArn`.
5. Ejecutar la plataforma indicando `-DeploymentRoleArn`; el orquestador obtiene credenciales STS temporales y deja de usar el perfil bootstrap.

La plantilla no contiene Access Keys, no crea usuarios IAM y no almacena credenciales permanentes.

El bootstrap está automatizado con vista previa segura:

```powershell
./scripts/deploy-deployment-role.ps1
./scripts/deploy-deployment-role.ps1 -Execute -ApproveChangeSets -AwsProfile bootstrap -ExpectedAccountId 123456789012
```
