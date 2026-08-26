# Orquestación con Kubernetes — Entrega (Lemoncode)

Guía práctica de entrega de los tres ejercicios de Kubernetes del módulo de
orquestación. Los manifests y scripts viven en este directorio `solution/`.

```
solution/
├── README.md                      # esta guía
├── ejercicio1.sh                  # Ejercicio 1: monolito en memoria
├── ejercicio2.sh                  # Ejercicio 2: monolito con PostgreSQL
├── ejercicio3.sh                  # Ejercicio 3: distribuido con Ingress
├── 00-monolith-in-mem/
│   ├── deployment.yml
│   └── service.yml
├── 01-monolith/
│   ├── postgres-configmap.yml
│   ├── storageclass.yml
│   ├── persistentvolume.yml
│   ├── persistentvolumeclaim.yml
│   ├── postgres-service.yml
│   ├── postgres-statefulset.yml
│   ├── todo-configmap.yml
│   ├── todo-deployment.yml
│   └── todo-service.yml
├── 02-distributed/
│   ├── todo-front-deployment.yml
│   ├── todo-front-service.yml
│   ├── todo-api-configmap.yml
│   ├── todo-api-deployment.yml
│   ├── todo-api-service.yml
│   └── ingress.yml
└── evidence/
    └── (se generan al ejecutar los scripts contra el clúster)
```

## Requisitos

- **Docker**: no es estrictamente necesario para los ejercicios, porque se usan las
  imágenes versionadas de Lemoncode ya publicadas en Docker Hub. Útil sólo si se
  quieren construir imágenes locales.
- **kubectl**: cliente instalado. Verificar con `kubectl version --client`.
- **Minikube**: instalado con el perfil `lemoncode-orchestration` arrancado.
  Verificar con `minikube --profile lemoncode-orchestration status`.
- **curl**: para la validación HTTP desde los scripts.
- **Verificación del contexto y perfil**: los tres scripts comprueban que el contexto
  activo de kubectl sea `lemoncode-orchestration` antes de aplicar nada y pasan ese
  perfil explícitamente a cada comando de Minikube. Si no coincide, el script aborta
  para no desplegar recursos de formación en un clúster ajeno. Para usarlo:
  ```bash
  kubectl config use-context lemoncode-orchestration
  ```

> Imágenes usadas (versionadas, **no** `:latest`):
> - `lemoncodersbc/lc-todo-monolith:v5-2024` (ejercicio 1)
> - `lemoncodersbc/lc-todo-monolith-psql:v5-2024` (ejercicio 2, PostgreSQL)
> - `lemoncodersbc/lc-todo-monolith-db:v5-2024` (ejercicio 2, app)
> - `lemoncodersbc/lc-todo-front:v5-2024` (ejercicio 3, frontend nginx)
> - `lemoncodersbc/lc-todo-api:v5-2024` (ejercicio 3, API express)

## Convenciones

- **Namespace dedicado por ejercicio**: `lemoncode-ej1`, `lemoncode-ej2`,
  `lemoncode-ej3`. Los manifests **no** llevan `namespace:` (se mantiene limpio y
  canónico); cada script los aplica en su namespace. Así los tres ejercicios son
  seguros en secuencia y no colisionan (p. ej. los dos `todo-app` de los
  ejercicios 1 y 2 viven en namespaces distintos).
- **Etiquetas**: `app`, `exercise` en los metadatos; selector de cada Service
  verificado contra las etiquetas del Pod template correspondiente.
- **APIs estables**: `apps/v1` (Deployments/StatefulSets), `v1` (Services,
  ConfigMaps, PV, PVC), `storage.k8s.io/v1` (StorageClass),
  `networking.k8s.io/v1` (Ingress). Sin APIs beta obsoletas.
- **Scripts ejecutables**: `ejercicio1.sh`, `ejercicio2.sh`, `ejercicio3.sh` se
  entregan con modo `100755` y cabecera `#!/usr/bin/env bash` +
  `set -Eeuo pipefail`. Cada uno admite:
  - ejecución normal (salida concisa),
  - `--debug` (sólo aumenta verbosidad, no cambia el comportamiento funcional),
  - `cleanup` (borra sólo los recursos de ese ejercicio).

---

## Ejercicio 1 — Monolito en memoria

### Arquitectura

Un único `Deployment` con la app `lemoncodersbc/lc-todo-monolith:v5-2024`, que sirve
la UI (estática) y la API (`/api/`) en el mismo proceso. La persistencia de los
TODOs es **en memoria**: al reiniciar el pod se pierden los datos (esperado en este
ejercicio). La app escucha en el puerto 3000 por defecto.

### Manifests

- `00-monolith-in-mem/deployment.yml`: `Deployment` `todo-app` con `NODE_ENV=production`
  y `PORT=3000`, `containerPort: 3000`. Incluye sondas `readinessProbe`/`livenessProbe`
  contra el endpoint real `/live/` que implementa `src/app.ts` (no es un endpoint
  inventado).
- `00-monolith-in-mem/service.yml`: `Service` tipo **LoadBalancer**, selector `app: todo-app`,
  puerto 80 → `targetPort: http` (3000).

### Cómo ejecutar

```bash
cd solution
./ejercicio1.sh            # despliega, espera y valida
./ejercicio1.sh --debug    # modo verbose
./ejercicio1.sh cleanup    # borra solo los recursos del ejercicio 1
```

### Deployment y LoadBalancer

El script crea el namespace `lemoncode-ej1`, aplica ambos manifests, espera con
`kubectl rollout status deployment/todo-app` a que el Deployment esté disponible y
muestra el estado de Deployment/Pods/Service.

### Cómo acceder a la aplicación

En Minikube con driver Docker, dos `LoadBalancer` simultáneos pueden compartir el
endpoint local del túnel (por ejemplo, `127.0.0.1:80`). Para que la validación no
pueda cruzar ejercicios, el script conserva el `Service` `LoadBalancer` solicitado
pero abre un `kubectl port-forward` exclusivo para ese Service:

```bash
kubectl --context lemoncode-orchestration -n lemoncode-ej1 \
  port-forward service/todo-app 18081:80
```

La validación automática usa `http://127.0.0.1:18081` y cierra ese proceso al
terminar. Un `minikube tunnel` sigue siendo útil para comprobar el comportamiento
propio de `LoadBalancer`, pero no se usa para identificar qué ejercicio atiende
una petición HTTP.

### Validación

El script valida a nivel HTTP (no sólo estado de pods):

1. `GET /live/` → salud.
2. `GET /api/` → lista de TODOS (inicialmente vacía).
3. `POST /api/` con un TODO de control → espera respuesta `ok` (201).
4. `GET /api/` → confirma que el TODO creado aparece.
5. `GET /` → confirma que se sirve la UI (HTML con `Todos App`).

### Limpieza

```bash
./ejercicio1.sh cleanup
```
Borra el namespace `lemoncode-ej1` (Deployment + Service). No toca otros recursos.

---

## Ejercicio 2 — Monolito con PostgreSQL

### Arquitectura

Capa de persistencia con PostgreSQL (StatefulSet + volumen persistente) y la app
`lemoncodersbc/lc-todo-monolith-db:v5-2024` que se conecta a la base de datos vía
descubrimiento de servicios (DNS del clúster).

### Recursos de PostgreSQL

- `postgres-configmap.yml`: `ConfigMap` `postgres-config` con `POSTGRES_USER` y
  `POSTGRES_PASSWORD`. **Importante**: la imagen base es `postgres:16`, que **obliga**
  a definir `POSTGRES_PASSWORD` (sin él el contenedor no arranca). Se fija a `postgres`
  para coincidir con `DB_PASSWORD` de la app. **No** se define `POSTGRES_DB`: el
  script de inicialización `todos_db.sql` ya contiene `CREATE DATABASE todos_db`; si se
  fijara `POSTGRES_DB=todos_db`, postgres:16 crearía la BD antes de los scripts init y
  entonces `CREATE DATABASE todos_db` fallaría con "database already exists" bajo
  `ON_ERROR_STOP=on`, abortando la inicialización. El README de Docker del repo usa un
  comando `docker run postgres:16` sin password; ese comando es **obsoleto** para
  postgres:16 y no se ha copiado a ciegas.
- `storageclass.yml`: `StorageClass` `postgres-storage`.
- `persistentvolume.yml`: `PersistentVolume` `postgres-pv` (2Gi, `ReadWriteOnce`,
  `Retain`, `hostPath` `/mnt/data/lemoncode-postgres` dentro del nodo de Minikube).
- `persistentvolumeclaim.yml`: `PersistentVolumeClaim` `postgres-pvc` (2Gi,
  `ReadWriteOnce`, `storageClassName: postgres-storage`).
- `postgres-service.yml`: `Service` **ClusterIP** `postgres` (5432). Selector
  `app: postgres` contra el StatefulSet.
- `postgres-statefulset.yml`: `StatefulSet` `postgres` con la imagen
  `lemoncodersbc/lc-todo-monolith-psql:v5-2024` (hereda de `postgres:16` y añade
  `todos_db.sql` a `docker-entrypoint-initdb.d`), monta el PVC en
  `/var/lib/postgresql/data` y carga la config del ConfigMap. Incluye un
  `initContainer` (`busybox`) que deja el directorio de datos con permisos correctos
  (UID 999 de postgres) para el `hostPath` del nodo de Minikube.

### ConfigMap de todo-app

- `todo-configmap.yml`: `ConfigMap` `todo-app-config` con `NODE_ENV`, `PORT` y las
  `DB_*` obligatorias. **`DB_HOST=postgres`** (nombre del Service ClusterIP, no
  `localhost`) para usar descubrimiento de servicios. `DB_USER=postgres`,
  `DB_PASSWORD=postgres`, `DB_PORT=5432`, `DB_NAME=todos_db`, `DB_VERSION=10.4`.

### Deployment y LoadBalancer

- `todo-deployment.yml`: `Deployment` `todo-app` con `envFrom` el ConfigMap y sondas
  contra `/live/`.
- `todo-service.yml`: `Service` **LoadBalancer** `todo-app` (80 → 3000).

### Descubrimiento de la BD

`DB_HOST=postgres` resuelve al Service ClusterIP dentro del clúster. La app
(`src/dals/dataAccess.ts`) usa Knex con esos parámetros. Nunca se usa `localhost`.

### Cómo ejecutar

```bash
cd solution
./ejercicio2.sh            # despliega y valida (incluye prueba de persistencia)
./ejercicio2.sh --debug
./ejercicio2.sh cleanup         # borra cargas de trabajo; CONSERVA namespace y datos
./ejercicio2.sh cleanup-data    # borra cargas y destruye sólo el almacenamiento del ejercicio
```

El script aplica en orden sensato: StorageClass → PV → PVC → config Postgres →
Service Postgres → StatefulSet Postgres; espera a que el PVC quede `Bound` y a que
el StatefulSet esté listo; verifica la BD; y luego aplica ConfigMap/Deployment/Service
de la app.

### Inicialización de la base de datos

La imagen `lemoncodersbc/lc-todo-monolith-psql:v5-2024` ya incluye `todos_db.sql` en
`docker-entrypoint-initdb.d`, de modo que al inicializar un volumen **vacío** crea la
BD `todos_db`, el esquema y semilla 3 TODOS (`Learn Jenkins`, `Learn GitLab`,
`Learn K8s`). **No** hace falta hacer `kubectl exec` con SQL a mano. El script
verifica la inicialización consultando directamente:

```bash
kubectl exec <postgres-pod> -n lemoncode-ej2 -- psql -U postgres -d todos_db -t -c "SELECT count(*) FROM todos;"
```

> Si se reutiliza un PV ya inicializado, `docker-entrypoint-initdb.d` **no** se
> vuelve a ejecutar (es comportamiento estándar de la imagen oficial de Postgres:
> sólo corre esos scripts cuando el directorio de datos está vacío). Para forzar un
> re-seed hay que destruir los datos (ver Limpieza).

### Validación de persistencia (núcleo del ejercicio)

El script `ejercicio2.sh` verifica la persistencia de forma real:

1. Abre `http://127.0.0.1:18082` mediante un `port-forward` exclusivo del Service
   `lemoncode-ej2/todo-app`.
2. Crea un TODO de control con título único vía `POST /api/` (escribe en Postgres)
   y exige con `psql` que el conteo exacto de ese título sea mayor que cero.
3. Lee los TODOS con `GET /api/` y los guarda como "antes".
4. **Recrea el pod de PostgreSQL** con `kubectl delete pod <postgres-pod>` **sin
   borrar el PVC/PV**.
5. Espera a que el StatefulSet vuelva a estar listo y recrea también el pod de
   `todo-app` para que reabra la conexión Knex con Postgres (no afecta a la
   persistencia: los datos viven en Postgres, no en la app).
6. Vuelve a leer los TODOS con `GET /api/` y exige que el TODO de control siga.
7. Exige de nuevo con `psql` que el conteo exacto sea mayor que cero. Un resultado
   `0` es un fallo, no una confirmación.

Esto demuestra que los datos sobreviven a la recreación del pod porque viven en el
PVC/PV, no en el contenedor.

### Ambigüedad StorageClass / aprovisionamiento dinámico

El enunciado pide a la vez:
- un `StorageClass` "para el aprovisionamiento dinámico", **y**
- crear explícitamente un `PersistentVolume`, **y**
- crear un `PersistentVolumeClaim`.

Esto es contradictorio: en un **aprovisionamiento dinámico real**, el
`provisioner` del StorageClass crea el PV automáticamente cuando aparece el PVC; un
PV escrito a mano sobraría y, además, con la mayoría de provisionadores el PV manual
no se enlazaría.

Para este trabajo de formación priorizamos **cumplir literalmente** con los recursos
solicitados por el enunciado (StorageClass + PV + PVC). Por eso se implementa un
**binding estático con identidad de StorageClass**:

- `StorageClass` `postgres-storage` con `provisioner: kubernetes.io/no-provisioner`
  (sin provisionador dinámico real).
- `PV` y `PVC` comparten el mismo `storageClassName: postgres-storage`, mismo tamaño
  (2Gi) y mismo `accessModes` (`ReadWriteOnce`), de modo que el PVC se enlaza al PV
  manualmente creado.

**Esto NO es aprovisionamiento dinámico real**: el PV está creado a mano y el PVC se
enlaza a él. El aprovisionamiento dinámico real **omitiría** el `PersistentVolume`
de este directorio y dejaría que el provisionador lo crease. Queda documentado así
para no fingir que el PV manual es dinámicamente aprovisionado. El `hostPath` apunta
a un directorio del **nodo de Minikube** (no del host), apropiado para un clúster
local de un solo nodo.

### Limpieza

```bash
./ejercicio2.sh cleanup          # borra cargas; conserva namespace, PVC, PV, StorageClass y datos
./ejercicio2.sh cleanup-data     # borra cargas, PVC, PV, StorageClass y el hostPath del ejercicio
```

Por defecto `cleanup` borra sólo el `StatefulSet` de PostgreSQL, el `Deployment` de
la aplicación, sus Services y ConfigMaps. Conserva el namespace `lemoncode-ej2`, el
PVC, el PV, el StorageClass y `/mnt/data/lemoncode-postgres`, por lo que un nuevo
despliegue puede reutilizar los datos. `cleanup-data` primero realiza esa limpieza de
cargas y después borra únicamente el PVC `postgres-pvc`, el PV `postgres-pv`, el
StorageClass `postgres-storage` y el directorio hostPath fijo a través del perfil
`lemoncode-orchestration`. El namespace se conserva vacío.

---

## Ejercicio 3 — Aplicación distribuida con Ingress

### Arquitectura

Dos servicios internos (ClusterIP) expuestos al exterior por un único `Ingress`
del controlador nginx de Minikube:

- `todo-front` (nginx, puerto 80): sirve la UI estática.
- `todo-api` (express/node, puerto 3000): sirve la API en `/api/`.

**No** se despliega PostgreSQL en este ejercicio: el enunciado y el código fuente
de `todo-api` son autoritativos, y su DAL es **en memoria** (`src/dals/todos/todo.dal.ts`).
La mención a Postgres en el README padre se refiere a la arquitectura general, no a
este ejercicio concreto.

### Manifests

- `todo-front-deployment.yml` + `todo-front-service.yml`: Deployment `todo-front`
  (imagen `lemoncodersbc/lc-todo-front:v5-2024`, puerto 80) + Service ClusterIP (80).
- `todo-api-configmap.yml`: ConfigMap opcional con `NODE_ENV` y `PORT`.
- `todo-api-deployment.yml` + `todo-api-service.yml`: Deployment `todo-api`
  (imagen `lemoncodersbc/lc-todo-api:v5-2024`, puerto 3000) + Service ClusterIP (80 → 3000).
- `ingress.yml`: Ingress `todo-ingress`.

### Controlador de Ingress

El script `ejercicio3.sh`:

1. Verifica/activa el addon `ingress` de Minikube
   (`minikube --profile lemoncode-orchestration addons enable ingress`).
2. Espera a que exista el namespace `ingress-nginx` y a que el pod del controlador
   esté `ready`.
3. Detecta la `IngressClass` (espera `nginx`; si no existe, usa la disponible).

No se asume que crear un recurso `Ingress` instale un controlador. Se usa
`ingressClassName: nginx` (API `networking.k8s.io/v1`), **no** la anotación obsoleta
`kubernetes.io/ingress.class`.

### Mapeo de rutas (mismo origen, sin rewrites)

```
/        -> Service todo-front  (nginx: HTML/JS estático)
/api     -> Service todo-api    (express: GET/POST/PATCH/DELETE /api/...)
```

Sin `rewrite-target`: la API ya sirve rutas bajo `/api/` (verificado en
`todo-api/src/app.ts`: `app.get('/api/', ...)`, `app.get('/api/:id/', ...)`, etc.).
El path que llega al Service `todo-api` es exactamente el que espera express.

### Por qué se omite API_HOST (y por qué no filtrar DNS interno al navegador)

El `Dockerfile` del frontend tiene `ARG API_HOST`, pero el enunciado dice que **se
puede omitir** en este ejercicio. El frontend (`todo.service.ts`) construye la URL así:

```ts
const host = () => (process.env.API_HOST ? process.env.API_HOST : "");
// axios.get(`${host()}/api/`)
```

Cuando `API_HOST` está vacío, `host()` devuelve `""` y todas las llamadas API son
**relativas al mismo origen** (`/api/`). Por eso:

- **No** se debe hornear `http://todo-api:3000` en el JS: `todo-api` es un nombre DNS
  **interno del clúster** que el navegador del usuario **no puede resolver**.
- Con el Ingress sirviendo frontend y API en el **mismo origen público**, las
  llamadas relativas `/api/` llegan al Service `todo-api` sin necesidad de CORS y sin
  exponer DNS interno al navegador. Esta es la arquitectura elegida.

### Cómo ejecutar

```bash
cd solution
./ejercicio3.sh            # despliega y valida
./ejercicio3.sh --debug
./ejercicio3.sh cleanup    # borra solo los recursos del ejercicio 3
```

### URL de acceso y validación

Con el driver Docker, `.status.loadBalancer.ingress` puede mostrar la IP privada del
nodo, que no es accesible desde Windows. Mantén en ejecución:

```bash
minikube --profile lemoncode-orchestration tunnel
```

El script valida el Ingress mediante el endpoint publicado por ese túnel:

```
http://127.0.0.1/        -> frontend
http://127.0.0.1/api/    -> API
```

Validación del script:

1. `GET /` → HTML del frontend con `Todos App`.
2. `GET /api/` → lista de TODOS vía Ingress (mismo origen).
3. `POST /api/` con un TODO de control → confirma escritura.
4. `GET /api/` → confirma que el TODO aparece (el frontend puede leer datos de la API).
5. Verifica que los assets JS del frontend (bundle de webpack) se sirven vía Ingress.

Esto confirma que el frontend carga y usa datos reales de la API a través del Ingress.

### Limpieza

```bash
./ejercicio3.sh cleanup
```
Borra el namespace `lemoncode-ej3` (Deployments, Services e Ingress). No desactiva el
addon `ingress` de Minikube (puede usarse en otros ejercicios).

---

## Evidencias

Los scripts generan evidencia real (no fabricada) bajo `solution/evidence/` al
ejecutarse contra el clúster:

- `evidence/ejercicio1-resources.txt` — Deployment/Pods/Service y respuestas HTTP.
- `evidence/ejercicio2-resources.txt` — StatefulSet/Deployment/Pods/Services/PV/PVC
  y respuestas HTTP, conteo de filas en `todos`.
- `evidence/ejercicio2-storage.txt` — StorageClass/PV/PVC.
- `evidence/ejercicio3-resources.txt` — Deployments/Pods/Services/Ingress/IngressClass
  y respuestas HTTP de frontend y API.
- `evidence/ejercicio3-ingress.txt` — Ingress y IngressClass detallados.
