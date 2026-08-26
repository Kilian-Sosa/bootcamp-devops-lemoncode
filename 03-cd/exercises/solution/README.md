# Solucion de Continuous Delivery

Esta entrega usa la pista de **Jenkins** y completa los dos opcionales de
GitHub Actions. No implementa la pista de GitLab.

## Matriz de entrega

| Ejercicio | Implementacion | Estado de validacion |
| --- | --- | --- |
| J1: pipeline Gradle declarativa | `jenkins-resources/Jenkinsfile` con Checkout, Compile y Unit Tests | Pipeline from SCM ejecutada correctamente en `*/feat/cd-exercises-solution` |
| J2: Jenkins con DinD | `solution/jenkins/` | Compose, plugins, TLS y montaje del workspace Jenkins -> DinD validados con la Pipeline real |
| A1: CI frontend | `.github/workflows/hangman-front-ci.yml` | Build y test locales validados con Node 24; ejecucion remota de la PR #3 correcta |
| A2: GHCR manual | `.github/workflows/hangman-front-publish.yml` | Configuracion y build local validados; publicacion pendiente de `workflow_dispatch` tras merge |
| A3: E2E | `.github/workflows/hangman-e2e.yml` | API, frontend y los dos specs Cypress suministrados validados localmente y en la PR #3 |
| A4: accion `motivate` | `.github/actions/motivate/` y workflow | Rutas de cita y fallback validadas localmente; evento `issues:labeled` pendiente de rama por defecto |

Las aplicaciones de trabajo estan en `hangman-front/`, `hangman-api/` y
`hangman-e2e/`. Son copias de `.start-code`; esa fuente se conserva sin
modificar.

## Jenkins

`03-cd/exercises/jenkins-resources/Jenkinsfile` es una Pipeline Declarative.
Hace `checkout scm` y ejecuta `./gradlew compileJava` y `./gradlew test` desde
`03-cd/exercises/jenkins-resources/calculator` mediante el agente Docker exacto
`gradle:7.6.6-jdk17`.

La configuracion DinD usa un daemon `docker:24.0.7-dind` separado, privilegiado
y con TLS. Jenkins lleva Docker CLI y los plugins `docker-plugin` y
`docker-workflow`; se conecta al alias TLS `docker:2376`. No monta el socket
Docker del host. Vease `jenkins/README.md`.

## GitHub Actions

- La CI se dispara solo con `pull_request` que cambie `hangman-front/**`, usa
  Node 24, `npm ci`, `npm run build` y `npm test`, con `contents: read`.
- El workflow de GHCR se dispara solo con `workflow_dispatch`, usa
  `contents: read` y `packages: write`, y publica
  `ghcr.io/kilian-sosa/hangman-front`. El nombre es estatico y en minusculas:
  no depende de que `github.repository_owner` ya venga normalizado.
- El E2E crea las imagenes, arranca API en `3001:3000` y frontend en
  `8080:8080`, espera respuestas HTTP, ejecuta `npx cypress run` y limpia
  siempre contenedores y red.
- `motivate-issue.yml` escucha `issues:labeled` y exige que la etiqueta anadida
  sea exactamente `motivate`. La accion JavaScript usa Node 24, registra el
  mensaje y tiene fallback local si falla type.fit.

## Ajustes minimos a las copias ejecutables

- El Dockerfile del frontend propaga el placeholder `{{API_URL}}` al build.
- `entry-point.sh` usa LF para que `sed` se ejecute dentro de la imagen Linux.
- El `prebuild` de la API usa `fs.rmSync`, en lugar de `rm -rf`, para poder
  validar tambien desde Windows sin cambiar dependencias.
- `.gitattributes` conserva LF en scripts shell y en el wrapper de Gradle.
- El test de frontend ahora espera los dos temas que devuelve su propio stub.

## Evidencia local y remota real (25-26-08-2026)

El detalle y los limites estan en `evidence/validation-2026-08-25.md`.

Se ejecutaron con exito:

- frontend: `npm ci`, `npm run build`, `npm test` con Node 24.16.0 (1 test);
- API: `npm ci`, `npm run build`, `npm test` con Node 24.16.0 (1 test);
- imagenes Docker de API y frontend, HTTP API y frontend, y sustitucion real de
  `API_URL` en el bundle servido;
- Cypress 10.10.0 en modo headless: 2 specs, 2 tests correctos;
- `./gradlew compileJava` y `./gradlew test` en `gradle:7.6.6-jdk17`;
- `docker compose config`, Jenkins HTTP 200, plugins requeridos y
  `docker version` desde Jenkins hasta DinD por TLS.
- GitHub Actions de la PR #3: **Frontend CI** y **Hangman E2E** correctos en
  el commit `a6d0e28`.
- Jenkins Pipeline from SCM sobre `*/feat/cd-exercises-solution`: **Checkout**,
  **Compile** y **Unit Tests** correctos con `gradle:7.6.6-jdk17` y DinD.

Los dos specs Cypress suministrados se conservaron sin cambios y se ejecutaron
tal como exige el ejercicio.

## Verificaciones pendientes por diseno

Los resultados remotos disponibles son los de la PR #3: **Frontend CI** y
**Hangman E2E** terminaron correctamente. No se afirma ninguna ejecucion no
indicada a continuacion.

1. Tras merge a la rama por defecto, disparar **Frontend Publish (GHCR)** y
   comprobar el paquete en GHCR.
2. Tras merge, crear una issue de prueba y anadir `motivate`; comprobar los
   logs de **Motivate Issue**. Los workflows `workflow_dispatch` e
   `issues:labeled` se resuelven desde la rama por defecto.
