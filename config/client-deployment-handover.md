# Acta de despliegue y entrega de FSG E-learning para EPICO

Este documento se completa después del despliegue y constituye la documentación que puede entregarse al cliente. Describe lo instalado y cómo solicitar soporte. No contiene ni concede acceso al código fuente propiedad de FSG.

## 1. Identificación

| Dato | Valor |
| --- | --- |
| Cliente | EPICO |
| Solución | FSG E-learning |
| Ambiente | Producción |
| Cuenta AWS | `<12 dígitos>` |
| Región principal | `us-east-1` |
| Fecha de despliegue | `<fecha>` |
| Responsable FSG | `<nombre>` |
| Responsable de aceptación EPICO | `<nombre>` |
| Centro de costo | `FSG-ELRN-EPICO-PROD` |

## 2. Alcance entregado

- Portal público alojado en AWS Amplify.
- Consola administrativa alojada en AWS Amplify.
- Identidad de usuarios mediante Amazon Cognito.
- Primer administrador asignado por EPICO.
- APIs de Auth, Course, Menu, Metrics, Subscriptions, Users y Videos.
- Tablas Amazon DynamoDB con recuperación a un punto en el tiempo.
- Almacenamiento privado Amazon S3.
- Distribución multimedia mediante Amazon CloudFront.
- Secretos operativos almacenados en AWS Secrets Manager.
- Etiquetas para inventario y análisis de costos.

No forman parte de la entrega: repositorios Git, código fuente, scripts de despliegue, archivos `.env`, parámetros internos, credenciales de GitHub/Serverless ni herramientas de desarrollo.

## 3. Inventario AWS

| Componente | Nombre/identificador | Estado |
| --- | --- | --- |
| Stack de rol | `<RESOURCE_PREFIX>-deployment-role-<ENVIRONMENT>` | `<estado>` |
| Stack Amplify | `<RESOURCE_PREFIX>-amplify-<ENVIRONMENT>` | `<estado>` |
| Stack compartido | `<RESOURCE_PREFIX>-platform-<ENVIRONMENT>` | `<estado>` |
| Stack Auth | `<nombre>` | `<estado>` |
| Stack Course | `<nombre>` | `<estado>` |
| Stack Menu | `<nombre>` | `<estado>` |
| Stack Metrics | `<nombre>` | `<estado>` |
| Stack Subscriptions | `<nombre>` | `<estado>` |
| Stack Users | `<nombre>` | `<estado>` |
| Stack Videos | `<nombre>` | `<estado>` |
| Cognito User Pool | `<id/nombre>` | `<estado>` |
| Bucket multimedia | `<nombre>` | `<estado>` |
| CloudFront | `<id>` | `<estado>` |

## 4. Direcciones entregadas

| Uso | URL |
| --- | --- |
| Portal público | `<https://...>` |
| Consola administrativa | `<https://...>` |
| CDN multimedia | `<https://...cloudfront.net>` |
| Dominio personalizado, si existe | `<https://...>` |

Las URLs internas de API se documentan en el expediente operativo de FSG y se entregan al cliente solamente si son necesarias para una integración autorizada.

## 5. Administrador inicial

| Dato | Valor |
| --- | --- |
| Correo | `<administrador@cliente>` |
| Grupo | `epico-administrators-production` |
| Fecha de creación | `<fecha>` |
| Cambio de contraseña confirmado | `<sí/no>` |

La contraseña no se escribe en este documento. Usuario y clave inicial se entregan por canales separados. EPICO debe comunicar inmediatamente cualquier cambio de responsable.

## 6. Seguridad y acceso

- EPICO es propietario de su cuenta AWS y controla quién accede a ella.
- FSG utiliza acceso temporal/autorizado para despliegue y soporte.
- Los usuarios finales no necesitan AWS CLI ni acceso a AWS Console.
- Los secretos permanecen en AWS Secrets Manager.
- El bucket S3 no es público; el contenido se entrega mediante CloudFront.
- El User Pool, bucket y tablas críticas tienen protecciones de retención/recuperación.
- El acceso administrativo requiere autenticación y pertenencia al grupo administrativo.

## 7. Costos

Los recursos usan las etiquetas comunes `Solution`, `Project`, `Client`, `Environment`, `Owner`, `ManagedBy`, `CostCenter` y `Service`. AWS puede tardar en reflejar datos en Cost Explorer. El consumo real depende de usuarios, almacenamiento, transferencia, ejecuciones y solicitudes.

## 8. Pruebas de aceptación

| Prueba | Resultado | Evidencia/observación |
| --- | --- | --- |
| Acceso al portal público | `<aprobado>` | `<detalle>` |
| Acceso del administrador | `<aprobado>` | `<detalle>` |
| Rechazo de usuario no administrador | `<aprobado>` | `<detalle>` |
| Gestión de usuarios | `<aprobado>` | `<detalle>` |
| Gestión de cursos y menús | `<aprobado>` | `<detalle>` |
| Gestión/reproducción de videos | `<aprobado>` | `<detalle>` |
| Métricas y reportes | `<aprobado>` | `<detalle>` |
| Suscripciones | `<aprobado>` | `<detalle>` |
| Carga S3 y entrega CloudFront | `<aprobado>` | `<detalle>` |

## 9. Operación y soporte

| Concepto | Valor |
| --- | --- |
| Canal de soporte FSG | `<correo/teléfono/sistema>` |
| Horario/SLA | `<detalle contractual>` |
| Responsable de incidentes EPICO | `<nombre/canal>` |
| Mantenimiento programado | `<procedimiento>` |

Cambios de infraestructura, actualizaciones y nuevas versiones son ejecutados por FSG mediante su proceso controlado. EPICO no necesita ni recibe el código fuente para operar la solución desplegada.

## 10. Exclusiones y cambios futuros

- No se incluyen migraciones de datos históricos.
- El dominio personalizado se incorpora solamente si EPICO acredita el dominio y autoriza los cambios DNS.
- Integraciones nuevas, habilitación de MFA y ampliaciones funcionales requieren evaluación y aprobación.
- No realizar modificaciones manuales en recursos administrados como IaC sin coordinación con FSG.

## 11. Aceptación

| Parte | Nombre | Fecha | Aprobación |
| --- | --- | --- | --- |
| FSG | `<nombre>` | `<fecha>` | `<firma/confirmación>` |
| EPICO | `<nombre>` | `<fecha>` | `<firma/confirmación>` |
