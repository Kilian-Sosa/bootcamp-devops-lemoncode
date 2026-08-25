# Jenkins local (Docker-in-Docker) - Ejercicios CD

Este directorio levanta un Jenkins reproducible que cumple el **Ejercicio 2**
de Jenkins: Jenkins con **Docker in Docker**, con los plugins **Docker** y
**Docker Pipeline** instalados, de forma que la pipeline declarativa del
`Jenkinsfile` use `gradle:7.6.6-jdk17` como build runner.

## Arquitectura (DinD real, no socket del host)

```
        +-------------------+       TLS (2376)        +-------------------+
        |  jenkins (CLI +   |  ----------------------> |  dind (Docker daemon)|
        |  plugins Docker)  |  DOCKER_HOST=tcp://docker|  alias TLS: docker   |
        +-------------------+   DOCKER_CERT_PATH=/certs +---------------------+
                |                         ^  (genera /certs/client)
                v                         |
          red `jenkins-net`  <--- volumen compartido `jenkins-dind-certs`
```

- `dind` arranca un **demonio Docker dentro del contenedor** y expone TLS.
- `jenkins` monta los **certificados de cliente** generados por `dind` en
  `/certs` y se conecta al alias TLS `tcp://docker:2376` con
  `DOCKER_TLS_VERIFY=1` y `DOCKER_CERT_PATH=/certs/client`.
- **No** se monta `/var/run/docker.sock`: eso NO seria Docker-in-Docker.
- Todo el trafico va por la red dedicada `jenkins-net`.

## Ficheros

| Fichero              | Descripcion                                            |
|----------------------|--------------------------------------------------------|
| `jenkins.Dockerfile` | Imagen Jenkins LTS (jdk17) + CLI Docker + plugins.    |
| `plugins.txt`        | Lista de plugins para `jenkins-plugin-cli`.            |
| `compose.yml`        | Orquesta `jenkins` + `dind` con TLS y red dedicada.    |

## Puesta en marcha

```bash
cd 03-cd/exercises/solution/jenkins

# Construye la imagen de Jenkins (CLI Docker + plugins) y arranca DinD.
docker compose up -d --build

# Comprueba la configuracion de compose (sin arrancar).
docker compose config

# Sigue el arranque de Jenkins.
docker compose logs -f jenkins
```

Jenkins estara disponible en `http://localhost:8080`.

> El asistente de instalacion inicial esta desactivado
> (`-Djenkins.install.runSetupWizard=false`) para el ejercicio local.

## Verificacion de conectividad DinD

```bash
# Desde el propio contenedor Jenkins: el CLI Docker debe alcanzar el dind.
docker compose exec jenkins docker version

# Debe mostrar tanto Client como Server (Server = demonio del contenedor dind).
docker compose exec jenkins docker info
```

Si `docker version` muestra un `Server`, el DinD funciona: Jenkins esta
hablando con un demonio Docker real dentro del contenedor `dind`.

## Verificacion del runner Gradle

La pipeline usa la imagen `gradle:7.6.6-jdk17`. Se puede validar fuera de
Jenkins que el runner compila y pasa los tests del `calculator`:

```bash
cd 03-cd/exercises/jenkins-resources/calculator
docker run --rm -v "$PWD:/workspace" -w /workspace gradle:7.6.6-jdk17 \
  sh -c "chmod +x ./gradlew && ./gradlew compileJava && ./gradlew test"
```

## Crear y ejecutar la pipeline desde Jenkins (pasos manuales)

El ejercicio no exige Configuration-as-Code completo. La creacion del job en
la UI es un paso manual minimo:

1. Abrir `http://localhost:8080`.
2. **New Item** -> nombre: `calculator-cd` -> **Pipeline** -> OK.
3. En la seccion **Pipeline**:
   - Definition: **Pipeline script from SCM**.
   - SCM: **Git**.
   - Repository URL: el repositorio remoto de GitHub
     (`https://github.com/<owner>/<repo>.git`).
   - Branch Specifier: la rama donde vive el `Jenkinsfile` (p. ej.
     `*/feat/cd-exercises-solution` o `*/master`).
   - Script Path: `03-cd/exercises/jenkins-resources/Jenkinsfile`.
4. Guardar y **Build Now**.

La pipeline ejecutara:
- **Checkout** (`checkout scm`)
- **Compile** (`./gradlew compileJava` en `gradle:7.6.6-jdk17`)
- **Unit Tests** (`./gradlew test` en `gradle:7.6.6-jdk17`)

## Parar y limpiar

```bash
docker compose down           # para y elimina contenedores
docker compose down -v        # ademas borra volumenes (jenkins-home, dind-data, certs)
```
