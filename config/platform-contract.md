# Contrato de configuración de la plataforma

Este contrato conecta la infraestructura compartida con Serverless y los frontends sin almacenar secretos en Git.

## Entradas administradas por la solución

`config/naming.env` define identidad, prefijo, sufijo, ambiente, región y ruta SSM. `config/tags.env` define las etiquetas obligatorias. Un `.env` local puede sobrescribir valores no sensibles para una instalación concreta.

## Salidas de CloudFormation

La infraestructura debe publicar exactamente estos Outputs:

| Output de CloudFormation | Variable local | Consumidor |
| --- | --- | --- |
| `AwsAccountId` | `AWS_ACCOUNT_ID` | Validación y automatización |
| `CognitoUserPoolId` | `COGNITO_USER_POOL_ID` | Microservicios y frontends |
| `CognitoClientId` | `COGNITO_CLIENT_ID` | Frontends y validación de tokens públicos |
| `CognitoAdministratorsGroupName` | `COGNITO_ADMINISTRATORS_GROUP` | Consola administrativa y alta inicial |
| `CognitoAuthClientId` | `COGNITO_AUTH_CLIENT_ID` | Solo Auth; cliente confidencial |
| `CognitoClientSecretId` | `COGNITO_CLIENT_SECRET_ID` | Solo Auth |
| `MediaBucketName` | `MEDIA_BUCKET_NAME` | Course y Videos |
| `MediaCdnUrl` | `MEDIA_CDN_URL` | Course, Videos y frontends |
| `MediaCloudFrontDistributionId` | `MEDIA_CLOUDFRONT_DISTRIBUTION_ID` | Operación e invalidaciones |

`CognitoClientSecretId` es el nombre o ARN del secreto. El valor del Client Secret nunca es un Output, una variable de frontend ni un archivo `.env`.

## Archivo generado localmente

```powershell
.\scripts\export-cloudformation-outputs.ps1 -StackName epico-platform-production
```

Opcionalmente se puede indicar `-AwsProfile epico`. El archivo real `config/platform-outputs.env` está ignorado por Git; el archivo `.example` documenta únicamente el formato.

## Precedencia

```text
config/naming.env
-> config/tags.env
-> config/platform-outputs.env
-> config/service-outputs.env
-> .env local
```

## Validación previa al empaquetado

```powershell
.\scripts\validate-environment.ps1 -RequirePlatformOutputs
```

Esta modalidad exige outputs completos, región `us-east-1`, cuenta de 12 dígitos, bucket EPICO, URL de CloudFront, tags y ausencia de valores secretos en archivos de configuración.

## Distribución a consumidores

- Serverless recibe las variables después de ejecutar `load-environment.ps1`.
- Amplify recibe User Pool ID, `COGNITO_CLIENT_ID`, grupo administrativo, CDN y URLs públicas.
- Auth recibe `COGNITO_AUTH_CLIENT_ID`; los demás consumidores no reciben su secreto.
- Ningún frontend recibe `COGNITO_CLIENT_SECRET_ID` ni el contenido del secreto.
- Auth recibe el identificador del secreto y obtiene su valor en ejecución mediante su rol IAM.

Las URLs de API Gateway y su traducción a variables Vite se documentan en `config/frontend-contract.md`.
