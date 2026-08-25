# Validacion local — 25-08-2026

## Entorno

- Node `v24.16.0`, npm `12.0.2`.
- Docker Desktop Engine `29.7.2`; las operaciones Docker requirieron acceso
  elevado al daemon de Docker Desktop.
- No se ejecutaron workflows remotos, publicaciones GHCR ni eventos GitHub.

## Frontend y API

| Comando | Resultado |
| --- | --- |
| `hangman-front: npm ci && npm run build` | Correcto; webpack 5.74.0 compilo correctamente |
| `hangman-front: npm ci && npm test` | Correcto; 1 suite, 1 test |
| `hangman-api: npm ci && npm run build` | Correcto |
| `hangman-api: npm ci && npm test` | Correcto; 1 suite, 1 test |
| `docker build hangman-api` | Correcto |
| `docker build hangman-front` | Correcto |

La API respondio `200` en `http://localhost:3001/api/topics` con
`["clothes","vehicles"]`. El frontend respondio `200` en
`http://localhost:8080`; dentro de su bundle servido se verifico
`http://localhost:3001` y la ausencia de `{{API_URL}}`.

## E2E

El intento de ejecutar el binario Cypress nativo de Windows quedo bloqueado
porque el entorno impide el post-install de paquetes. Se ejecuto la misma
carpeta de specs con `cypress/included:10.10.0`, montada contra los servicios
temporales ya comprobados. Resultado: 2 specs, 2 tests correctos, salida 0.

Los specs proporcionados son vacios; este resultado valida que Cypress alcanza
el frontend y que los servicios arrancan, no una interaccion funcional de UI.
Los contenedores, red y videos generados se eliminaron al terminar.

## Jenkins

- `docker compose config`: correcto.
- `gradle:7.6.6-jdk17 ./gradlew compileJava`: `BUILD SUCCESSFUL`.
- `gradle:7.6.6-jdk17 ./gradlew test`: `BUILD SUCCESSFUL`.
- Jenkins mas DinD arrancaron, Jenkins devolvio HTTP 200 y el contenedor
  contenia `docker-plugin.jpi` y `docker-workflow.jpi`.
- `docker compose exec -T jenkins docker version`: correcto; cliente y daemon
  DinD informaron Docker `24.0.7` por TLS.

No se creo ni ejecuto un job Jenkins desde SCM porque la rama aun no esta
publicada en un remoto.

## Pendiente por diseno de GitHub

- La CI y E2E de PR requieren una PR remota.
- El publish GHCR requiere `workflow_dispatch` en la rama por defecto.
- `issues:labeled` requiere el workflow en la rama por defecto y una issue de
  prueba con la etiqueta `motivate`.
