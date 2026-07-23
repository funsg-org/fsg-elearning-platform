# Validacion continua

El workflow `.github/workflows/deployment-readiness.yml` se ejecuta en cada push de `feature/epico-deployment-readiness`, `develop`, `qa` o `production`; también en pull requests hacia las ramas de promoción y manualmente.

Comprueba sin credenciales AWS:

- sintaxis de todos los scripts PowerShell;
- correspondencia entre `.gitmodules` y los diez gitlinks;
- URLs y ramas estables declaradas para los submodulos;
- estructura de los contratos JSON;
- patrones de secretos en archivos rastreados;
- las dos plantillas mediante Python 3.13 y `cfn-lint` fijado en la version `1.53.1`.

El checkout no descarga los repositorios privados hijos: los gitlinks fijan los commits y cada repositorio conserva su propio CI. Esto evita almacenar un PAT transversal en el repositorio padre.

El workflow tiene permisos `contents: read`, no configura AWS y contiene un bloqueo que rechaza comandos de despliegue.
