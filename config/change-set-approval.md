# Aprobación de cambios CloudFormation

Los stacks `epico-deployment-role-production`, `epico-amplify-production` y `epico-platform-production` ya no usan `cloudformation deploy` directamente. `scripts/invoke-cloudformation-change-set.ps1` crea un change set y muestra:

- acción `Add`, `Modify`, `Remove` o `Import`;
- Logical ID y tipo de recurso;
- alcance de propiedades modificadas;
- si CloudFormation prevé reemplazo.

Sin `-ApproveExecution`, el change set queda creado pero no se ejecuta. Los orquestadores exigen `-ApproveChangeSets` para expresar la aprobación y ejecutan únicamente el change set recién mostrado.

```powershell
./scripts/deploy-platform.ps1 -Execute -ApproveChangeSets `
  -AwsProfile epico `
  -ExpectedAccountId 123456789012 `
  -DeploymentRoleArn arn:aws:iam::123456789012:role/epico-deployment-production
```

## Límite de Serverless

Los siete microservicios generan sus propios stacks CloudFormation dentro de Serverless Framework. Esta compuerta cubre los tres stacks administrados directamente por el repositorio padre; no intercepta el change set interno de `serverless deploy`. El orquestador mantiene despliegue secuencial y se detiene ante el primer error.
