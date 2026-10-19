# Política de seguridad

## Reportar una vulnerabilidad

Usa los **avisos privados de seguridad** de este repositorio
(*Security → Advisories → Report a vulnerability*). No publiques tokens,
credenciales ni detalles explotables en issues públicos.

## Modelo de seguridad

- **El instalador no escribe tokens.** La credencial la guarda GitHub CLI en el
  Administrador de credenciales de Windows.
- **Sin `delete_repo`.** El login por navegador concede `repo`, `read:org`,
  `gist` y `workflow`. La ausencia de `delete_repo` es la barrera que impide
  borrar repositorios por API. No la añadas.
- **Solo lectura por defecto.** Las instrucciones que se escriben en
  `AGENTS.md` prohíben crear, borrar o cambiar configuración sin petición
  explícita.
- **One-liner.** Ejecuta código remoto: apunta a un tag inmutable, no a `main`.
  La release publica el SHA256 del script. Si prefieres revisar antes, descarga
  el `.ps1` y ejecútalo con `-File`.
- **Ramas.** El scope `repo` permite escribir en ramas. Para protegerlas,
  activa branch protection o rulesets en GitHub.

## Versiones soportadas

La rama `main` y la última release `v1.x`.

## Alcance

Este proyecto instala y configura GitHub CLI; no implementa la autenticación ni
el almacenamiento de credenciales de GitHub. Esos quedan en manos de `gh` y del
sistema operativo.
