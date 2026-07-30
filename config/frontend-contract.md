# Contrato de configuración de frontends

Los dos frontends utilizan los mismos nombres para APIs y CDN. El portal administrativo agrega Cognito público.

## Variables comunes

- `VITE_AUTH_API_URL`
- `VITE_COURSE_API_URL`
- `VITE_MENU_API_URL`
- `VITE_METRICS_API_URL`: URL de la distribución CloudFront de métricas, no la URL directa de API Gateway.
- `VITE_SUBSCRIPTIONS_API_URL`
- `VITE_USERS_API_URL`
- `VITE_VIDEOS_API_URL`
- `VITE_MEDIA_CDN_URL`

El portal público agrega `VITE_BASE_PATH=/`. El administrativo agrega `VITE_COGNITO_USER_POOL_ID`, `VITE_COGNITO_CLIENT_ID` y `VITE_COGNITO_ADMINISTRATORS_GROUP`. El acceso exige pertenecer al grupo administrativo generado por la infraestructura.

## Flujo de generación

```powershell
.\scripts\export-cloudformation-outputs.ps1 -StackName "$($env:RESOURCE_PREFIX)-platform-$($env:ENVIRONMENT)"
.\scripts\export-serverless-outputs.ps1
.\scripts\export-amplify-environments.ps1
```

Los JSON `config/amplify-*-env.json` están ignorados por Git. El script no llama a Amplify ni cambia aplicaciones.

## Seguridad

- Vite solo recibe información pública.
- Ninguna variable `VITE_*` puede contener `SECRET`, `PASSWORD`, `AWS_ACCESS_KEY` o `TOKEN` en su nombre.
- `COGNITO_AUTH_CLIENT_ID` y `COGNITO_CLIENT_SECRET_ID` nunca se exportan a frontends.
- Los builds fallan cuando falta una variable obligatoria.
