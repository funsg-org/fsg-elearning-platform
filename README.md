# FSG E-learning Platform

Repositorio orquestador privado de FSG para administrar, versionar y validar la solución e-learning como una unidad.

Este repositorio no reemplaza los repositorios de los microservicios y frontends. Cada proyecto mantiene su historial y repositorio independiente; el padre registra, mediante Git submodules, el commit exacto de cada componente que integra una versión de la plataforma.

El nombre del repositorio padre no determina el nombre de los recursos AWS. El prefijo técnico del cliente se definirá posteriormente mediante la configuración común de la solución; para la instalación actual será `epico`.

## Estructura

```text
fsg-elearning-platform/
  services/
    ms-aprendamosgye-auth/
    ms-aprendamosgye-course/
    ms-aprendamosgye-menu/
    ms-aprendamosgye-metrics/
    ms-aprendamosgye-subscriptions/
    ms-aprendamosgye-users/
    ms-aprendamosgye-videos/

  frontends/
    aprendamosgye_app/
    aprendamosgye_react/
    ms-aprendamosgye-admin-web/

  infrastructure/
  config/
  scripts/
```

## Clonar la plataforma completa

La forma recomendada es clonar el padre junto con todos sus submodules:

```powershell
git clone --recurse-submodules https://github.com/funsg-org/fsg-elearning-platform.git
```

Si el repositorio padre ya fue clonado sin los proyectos hijos:

```powershell
git submodule update --init --recursive
```

El usuario o pipeline que ejecute estos comandos debe tener acceso de lectura a todos los repositorios privados registrados en `.gitmodules`.

## Consultar el estado de los submodules

Desde la raíz del padre:

```powershell
git submodule status
git status
```

Para consultar la rama y los cambios locales de cada hijo:

```powershell
git submodule foreach --recursive 'git status --short --branch'
```

Un prefijo `-` en `git submodule status` indica que el submodule todavía no se inicializó. Un prefijo `+` indica que el hijo está en un commit diferente al registrado por el padre.

## Modificar un repositorio hijo

Antes de editar un submodule, entrar al proyecto y cambiar explícitamente a su rama de trabajo. Un submodule recién clonado puede estar en estado `detached HEAD`.

Ejemplo con Courses:

```powershell
cd services/ms-aprendamosgye-course
git switch master
git pull --ff-only
```

Crear una rama cuando el cambio no deba realizarse directamente sobre la rama principal:

```powershell
git switch -c feature/descripcion-del-cambio
```

Después de implementar y validar el cambio, publicar primero en el repositorio hijo:

```powershell
git add <archivos>
git commit -m "refactor: descripción del cambio"
git push -u origin <rama>
```

Después de integrar el cambio en la rama estable del hijo, regresar al padre y registrar el nuevo commit del submodule:

```powershell
cd ../..
git status
git add services/ms-aprendamosgye-course
git commit -m "chore: update course service reference"
git push
```

El orden obligatorio es:

```text
commit y push en el hijo
-> integración en la rama estable del hijo
-> actualización del puntero en el padre
-> commit y push del padre
```

El padre no publica cambios pendientes que solo existan dentro del working tree de un hijo.

## Actualizar el padre respetando las versiones registradas

Para actualizar el repositorio padre y colocar cada hijo en el commit aprobado:

```powershell
git pull --ff-only
git submodule sync --recursive
git submodule update --init --recursive
```

Este es el procedimiento recomendado para entornos reproducibles y pipelines.

## Buscar nuevas versiones de las ramas configuradas

Para traer las últimas versiones de las ramas declaradas en `.gitmodules`:

```powershell
git submodule update --remote --merge
```

Después se deben revisar y probar los cambios antes de registrarlos:

```powershell
git status
git diff --submodule=log
```

Si las versiones son correctas:

```powershell
git add services frontends
git commit -m "chore: update platform submodules"
git push
```

No debe ejecutarse una actualización automática de todos los submodules directamente en producción sin revisión. El repositorio padre debe fijar versiones conocidas y probadas.

## Reglas de trabajo

- Los repositorios y carpetas actuales conservan sus nombres; los nombres AWS se configurarán por separado.
- Nunca guardar `.env`, access keys, Client Secrets, tokens GitHub ni otras credenciales en este repositorio.
- Los cambios de código se confirman y publican primero en el repositorio hijo.
- El padre registra únicamente el commit del hijo, no sus archivos como contenido normal.
- No dejar cambios importantes en un submodule en estado `detached HEAD`.
- No usar `git submodule update --remote` en un pipeline productivo sin una etapa de revisión y pruebas.
- No eliminar ni recrear la carpeta `.git` de un proyecto hijo.
- El acceso al repositorio padre no concede automáticamente acceso a los repositorios privados hijos.
- El pipeline del padre debe contar con credenciales de lectura para todos los submodules.
- Antes de confirmar un cambio del padre, revisar `git diff --submodule=log`.

## Diagnóstico común

Sincronizar URLs después de modificar `.gitmodules`:

```powershell
git submodule sync --recursive
```

Restaurar un hijo al commit registrado por el padre, siempre que no tenga cambios locales que deban conservarse:

```powershell
git submodule update --init --recursive services/ms-aprendamosgye-course
```

Ver la URL configurada para cada submodule:

```powershell
git config --file .gitmodules --get-regexp url
```

Ver los commits registrados por el padre:

```powershell
git submodule status --recursive
```
