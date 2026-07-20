# Contrato de secretos

Los secretos de la plataforma no se almacenan en Git, archivos `.env`, variables `VITE_*`, outputs de CloudFormation ni parámetros SSM de tipo `String`.

## Cognito del microservicio de autenticación

El microservicio `ms-aprendamosgye-auth` utiliza un App Client confidencial y necesita calcular `SECRET_HASH`. El valor se recupera en tiempo de ejecución desde AWS Secrets Manager.

Nombre lógico inicial del secreto:

```text
epico/production/cognito/auth-client-secret
```

Formato recomendado:

```json
{
  "clientSecret": "valor-generado-por-cognito"
}
```

También se acepta temporalmente un `SecretString` cuyo contenido completo sea el Client Secret, pero el formato JSON es el estándar de la solución.

La Lambda recibe únicamente:

```text
COGNITO_CLIENT_SECRET_ID=epico/production/cognito/auth-client-secret
```

Su rol permite exclusivamente `secretsmanager:GetSecretValue` sobre ese secreto. El secreto se carga de forma diferida y se conserva en memoria durante la vida del contenedor Lambda.

## Reglas obligatorias

- No usar AWS Access Keys estáticas dentro de los microservicios; Lambda debe usar su rol IAM.
- GitHub Actions debe usar OIDC o secretos protegidos de GitHub, nunca claves escritas en workflows.
- Los frontends no pueden recibir Client Secrets ni otras credenciales mediante variables `VITE_*`.
- Todo secreto previamente versionado se considera comprometido y debe deshabilitarse o reemplazarse en su sistema de origen.
- El repositorio padre solo conserva nombres o ARNs de secretos, nunca sus valores.

## Pendientes operativos

- Crear el App Client confidencial de EPICO durante la etapa IaC.
- Crear el secreto mediante CloudFormation o un procedimiento seguro sin imprimir el valor.
- Deshabilitar los Access Key IDs encontrados en el historial de los repositorios heredados.
- Reemplazar el App Client cuyo secreto apareció en el historial de `ms-aprendamosgye-auth`.
