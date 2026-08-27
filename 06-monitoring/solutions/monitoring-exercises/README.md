# Ejercicios de Monitoring — Solución

Solución de los ejercicios de monitoring del bootcamp DevOps Lemoncode.

Todo el trabajo del alumno vive bajo `06-monitoring/solutions/monitoring-exercises/`.
No se modifica `06-monitoring/00-prometheus/`.

Estado general:

| Ejercicio | Implementado | Ejecutado en local | Observable en navegador |
|---|---|---|---|
| 1. Prometheus auto-scrape | ✅ | ✅ | ✅ http://localhost:9090 |
| 2. Teoría Prometheus | ✅ | n/a | n/a |
| 3. Explicación carpeta Loki | ✅ | n/a | n/a |
| 4. Estructura traza Jaeger | ✅ | n/a | n/a |
| 5.1 Prometheus + FastAPI | ✅ | ✅ | ✅ http://localhost:8000 / http://localhost:9090 |
| 5.2 Jaeger / HotROD | ✅ | ✅ | ✅ http://localhost:16686 / http://localhost:8080 |

> Convención de marcado de evidencias: los archivos en `evidence/` se generan
> con la salida real de comandos. Los bloques pendientes (PENDIENTE) indican
> qué no pudo ejecutarse.

URLs (cuando cada setup está levantado):

- Prometheus (ej. 1): http://localhost:9090
- Prometheus (ej. 5.1): http://localhost:9090
- app_map: http://localhost:8000
- app_map /metrics: http://localhost:8000/metrics/
- Jaeger UI: http://localhost:16686
- HotROD: http://localhost:8080

---

## Estructura de la solución

```
06-monitoring/solutions/monitoring-exercises/
  README.md
  01-prometheus-self/
    compose.yml
    prometheus.yml
  05-prometheus-app/
    compose.yml
    prometheus.yml
    app_map/
      Dockerfile
      requirements.txt
      main.py
      __init__.py
      api/
        __init__.py
        endpoints.py
      schemas/
        __init__.py
        item.py
      statics/
        index.html
  05-jaeger-hotrod/
    compose.yml
    compose.fixed.yml
    NOTES.md
  evidence/
    prometheus-self.txt
    prometheus-app.txt
    jaeger-baseline.txt
    jaeger-fixed.txt
```

---

## Ejercicio 1 — Prometheus auto-scrape

### Objetivo

Levantar Prometheus con Docker, con una configuración mínima que haga scrape
del propio Prometheus, exponer el puerto web y ejecutar una consulta de memoria
y una de CPU.

### Configuración

`01-prometheus-self/prometheus.yml`:

```yaml
global:
  scrape_interval: 5s
  scrape_timeout: 3s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - prometheus:9090
```

`01-prometheus-self/compose.yml` usa la imagen fijada
`prom/prometheus:v3.14.0` (no `:latest`), expone `9090:9090` y monta la
configuración como solo lectura. Prometheus se scrapea a sí mismo a través de
la red de Docker usando el nombre de servicio `prometheus:9090`.

### Reproducción

```bash
cd 06-monitoring/solutions/monitoring-exercises/01-prometheus-self

# validación estática del Compose
docker compose config

# arranque
docker compose up -d

# esperar a que Prometheus esté listo (unos segundos)
docker compose ps

# target desde el host
curl -s http://localhost:9090/targets | head
# o vía API:
curl -s "http://localhost:9090/api/v1/targets" | head -c 2000
```

### Consultas (PromQL)

Consulta de memoria (memoria residente del proceso Prometheus en bytes):

```promql
process_resident_memory_bytes{job="prometheus"}
```

Consulta de CPU (segundos de CPU consumidos por segundo en el último minuto ≈
núcleos de CPU usados por el proceso):

```promql
rate(process_cpu_seconds_total{job="prometheus"}[1m])
```

### Interpretación de las métricas

- `process_resident_memory_bytes` es la memoria **residente del proceso
  Prometheus** en bytes (la memoria RAM que el proceso tiene realmente
  mapeada). **No** es la memoria total del host.
- `rate(process_cpu_seconds_total[1m])` representa los **segundos de CPU
  consumidos por segundo** por el proceso Prometheus en el rango de 1 minuto,
  es decir, de forma aproximada el número de núcleos de CPU que está usando el
  proceso. **No** es el uso total de CPU del host.

Ambas son métricas a nivel de **proceso de Prometheus**, no a nivel de host.

### Ejecución de las consultas por la API HTTP

```bash
# memoria
curl -s --data-urlencode 'query=process_resident_memory_bytes{job="prometheus"}' \
  http://localhost:9090/api/v1/query | head -c 2000

# cpu
curl -s --data-urlencode 'query=rate(process_cpu_seconds_total{job="prometheus"}[1m])' \
  http://localhost:9090/api/v1/query | head -c 2000

# estado del target
curl -s "http://localhost:9090/api/v1/targets" | head -c 2000
```

La salida real se captura en `evidence/prometheus-self.txt`. El target debe
estar **UP**.

### Limpieza

```bash
docker compose down
```

---

## Ejercicio 2 — Teoría: Prometheus

### Exporters

Los **exporters** exponen métricas de sistemas que no pueden o no conviene
instrumentar directamente con un cliente de Prometheus. Un exporter es un
pequeño proceso que conoce el sistema a monitorizar (una base de datos, un SO,
un balanceador…) y publica sus métricas en el formato de texto de Prometheus en
un endpoint HTTP `/metrics`.

Ejemplos habituales:

- **node_exporter**: métricas del SO Linux/Unix (CPU, memoria, disco, red) por
  host.
- **JMX exporter**: métricas de aplicaciones Java vía JMX (JVM, GC, pools…),
  útil para apps Java que no están instrumentadas directamente.
- **blackbox exporter**: sondeo externo "caja negra" (HTTP, HTTPS, ICMP, TCP) para
  medir disponibilidad y latencia desde fuera.

Es importante notar que **los exporters no "envían" (push) métricas a
Prometheus**. El modelo de Prometheus es de **pull/scrape**: Prometheus es quien
se conecta al exporter y recoge sus métricas en el intervalo configurado. (Sí
existen mecanismos de push puntuales como el Pushgateway, pero no es el modelo
habitual de los exporters.)

### Recording rules

Las **recording rules** (reglas de grabación) evalúan periódicamente una
expresión PromQL y **guardan el resultado como una nueva serie temporal** con un
nombre determinado. Son útiles para:

- consultas repetidas o costosas de calcular (se calculan una vez y se reutilizan);
- simplificar y precalcular expresiones complejas usadas en dashboards o alertas;
- aligerar la carga de consultas frecuentes.

Ejemplo pequeño y válido (en un fichero de reglas cargado por Prometheus):

```yaml
groups:
  - name: example
    rules:
      - record: job:prometheus_cpu_cores:rate1m
        expr: rate(process_cpu_seconds_total{job="prometheus"}[1m])
```

Esto crea la nueva serie `job:prometheus_cpu_cores:rate1m` con el valor
precalculado.

### Alert rules

Las **alerting rules** (reglas de alerta) evalúan periódicamente una **condición
PromQL** y, cuando se cumple, producen alertas con estado *pending* (pendiente)
y *firing* (disparada). La cláusula `for` permite exigir que la condición se
mantenga durante un tiempo antes de dispararse.

Ejemplo:

```yaml
groups:
  - name: example_alerts
    rules:
      - alert: PrometheusDown
        expr: up{job="prometheus"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "El target de Prometheus está caído"
```

Diferencia con las recording rules: las **recording rules** evalúan PromQL y
**almacenan el resultado como serie temporal** (no generan notificaciones). Las
**alerting rules** evalúan PromQL como **condición** y **generan alertas**
(pending/firing). En un setup completo, Prometheus envía las alertas *firing* a
**Alertmanager**, que se encarga del agrupado, enrutado, silenciado y envío de
notificaciones. En este ejercicio **no se monta Alertmanager**.

---

## Ejercicio 3 — Explicación de la carpeta Loki

Carpeta origen (referencia, **solo lectura**, rama `feature/iac-review` del
repo Lemoncode):

```
06-monitoring/01-exercise/01-start-up-loki
  docker-compose.yaml
  loki-config.yaml
  alloy-local-config.yaml
```

El material oficial se restaura sin modificaciones en `06-monitoring/01-exercise/`;
la solución lo analiza y no lo modifica. Tampoco se añaden servicios de Loki a
la solución (el ejercicio 3 pide explicar la carpeta).

La arquitectura de `docker-compose.yaml` **no es un único proceso Loki**, sino
un **layout distribuido de estilo Loki "simple scalable"** (microservicios read /
write / backend) detrás de un gateway nginx, con almacenamiento de objetos en
MinIO y observabilidad en Grafana.

### Componentes (`docker-compose.yaml`)

- **Loki `read`** (`target=read`): componente de lectura. Expone `3100`
  (mapeado a `3101` en host) y los puertos de memberlist (`7946`) y gRPC
  (`9095`). Se une al anillo (`memberlist`) y depende de MinIO.
- **Loki `write`** (`target=write`): componente de escritura (recibe los
  *pushes* de logs). Expone `3100` (mapeado a `3102`) y memberlist/gRPC.
- **Loki `backend`** (`target=backend`, `-legacy-read-mode=false`): el tercero
  del modo escalable; ejecuta tareas como compactor/ruler/index. Depende del
  gateway.
- **nginx `gateway`**: expone **un único endpoint Loki** en `3100` y enruta el
  tráfico: **writes/pushes** (`/loki/api/v1/push`, `/api/prom/push`) hacia el
  componente `write`, y **reads/tails/queries** (`/loki/api/...`,
  `/api/prom/tail`, etc.) hacia el componente `read`. Así los clientes usan una
  sola URL (`gateway:3100`) en vez de hablar con read/write por separado.
- **MinIO**: proporciona **almacenamiento de objetos compatible con S3** en
  local para el ejercicio (buckets `loki-data` y `loki-ruler`). Crea los
  directorios y arranca `minio server /data`.
- **Grafana**: visualización. En el entrypoint provisiona un datasource Loki que:
  - apunta a `http://gateway:3100` (el gateway nginx, no a read/write directos);
  - configura la cabecera de tenant (`X-Scope-OrgID` = `tenant1`) vía
    `jsonData.httpHeaderName1` / `secureJsonData.httpHeaderValue1`.
  Habilita auth anónima con rol Admin para el laboratorio.
- **Grafana Alloy** (`alloy`): el recolector. Descubre contenedores y lee sus
  logs (config en `alloy-local-config.yaml`) y los envía al gateway. Monta
  `docker.sock` para el *discovery*.
- **`flog`** (`mingrammer/flog`): generador que **produce logs JSON falsos de
  forma continua** (`-f json -d 200ms -l`), que Alloy recoge y reenvía a Loki.
- **Red Docker compartida `loki`**: todos los servicios están en la misma red
  `loki`, con alias `loki` para read/write para que memberlist funcione.

### `alloy-local-config.yaml`

- **Discovery Docker** vía `docker.sock` (`discovery.docker`), refrescando cada
  5s.
- **Relabeling** de metadatos de contenedor: extrae el nombre del contenedor
  (`__meta_docker_container_name`, quitando la `/` inicial) a la etiqueta
  `container`.
- **Lectura de logs de Docker** (`loki.source.docker`) desde `docker.sock` con
  las *relabel rules* anteriores.
- **Reenvío** de los logs a Loki mediante `loki.write`, cuyo endpoint es
  `http://gateway:3100/loki/api/v1/push` con `tenant_id = tenant1`.

### `loki-config.yaml`

- **Servidor HTTP** en `0.0.0.0:3100`.
- **memberlist** (anillo) entre `read`, `write` y `backend` (`join_members`),
  bind en `0.0.0.0:7946`, para que los tres nodos formen el anillo.
- **Esquema TSDB** con **schema v13** (`store: tsdb`, `schema: v13`), índice con
  prefijo `index_` y periodo 24h.
- **Almacenamiento de objetos S3-compatible** en MinIO
  (`endpoint: minio:9000`, `bucketnames: loki-data`, `s3forcepathstyle: true`).
- **`replication_factor: 1`** para el laboratorio local (sin réplicas).
- **Ruler storage**: bucket S3 `loki-ruler`.
- **Compactor** con directorio de trabajo `/tmp/compactor` (corre en el
  `backend`).

### Credenciales

El ejemplo contiene **credenciales locales de MinIO hard-coded** (`loki` /
`supersecret`, visibles en `loki-config.yaml` y en las variables de entorno de
MinIO). Esto es **aceptable solo para este ejemplo local de formación** y **no
es un patrón de gestión de secretos para producción**. En producción se usaría
un gestor de secretos / variables inyectadas, no credenciales en claro en el
repo.

---

## Ejercicio 4 — Estructura de una traza Jaeger

> Aclaración de terminología: el ejercicio original usa términos de la era
> OpenTracing/Jaeger (2017). Hoy el estándar es **OpenTelemetry**. Se explica
> en términos modernos manteniendo el enfoque del ejercicio.

### Trace (traza)

Una **traza** representa una operación end-to-end (por ejemplo, una petición
HTTP completa) y agrupa bajo un mismo **trace ID** todos los spans relacionados.
Es la unidad que permite reconstruir el recorrido completo de una solicitud a
través de varios servicios.

### Span

Un **span** representa una unidad de trabajo / operación dentro de la traza
(por ejemplo, una llamada HTTP, una consulta a BD, una operación interna).
Conceptos útiles:

- **span ID**: identificador único del span dentro de la traza.
- **trace ID**: identificador común a toda la traza (compartido por todos sus
  spans).
- **relación padre/hijo**: un span puede tener un span padre, lo que forma la
  jerarquía/causa-efecto de la traza.
- **operation/name**: nombre de la operación.
- **start/end/duration**: instante de inicio, fin y duración del span.
- **status**: estado/resultado (OK, error, etc.).
- **attributes/tags**: metadatos clave/valor (ver más abajo).
- **events/logs**: eventos puntuales dentro del span (p. ej. excepciones).

### Scope (Instrumentation Scope)

En terminología moderna (OpenTelemetry), **Instrumentation Scope** identifica
el **origen lógico de la instrumentación** que emitió el span: habitualmente
una librería / módulo / paquete y opcionalmente su versión. No se debe
confundir con:

- el *scope* léxico / de variables de un lenguaje de programación;
- el "scope" genérico de una traza/span en prosa.

El tutorial de HotROD de 2017 **precede a la terminología actual de
OpenTelemetry**, por lo que parte de su vocabulario está anticuado respecto al
estándar moderno.

### Tags

El término viejo **"tags"** de OpenTracing/Jaeger corresponde, de forma
aproximada, a los **span attributes** (atributos de span) de OpenTelemetry: son
**metadatos clave/valor que describen la operación**. Ejemplos:

- método HTTP (`http.method`);
- ruta (`http.route`);
- código de estado (`http.status_code`);
- sistema de base de datos (`db.system`).

Los tags **no son spans hijos**; son atributos del propio span.

---

## Ejercicio 5.1 — Prometheus + FastAPI app

### Origen de la app

App original: `app_map` del repositorio
https://github.com/JaimeSalas/non-political-map (`/app_map`).

- Repo upstream: https://github.com/JaimeSalas/non-political-map
- Commit de origen copiado: `0f3dae37277c061516eae2a8d373ba9b56c0c930` (rama `main`)

Solo se ha traído `app_map` (no `app_frontend`, `app_kpi_api`, ni ejemplos S3).
La app expone `/api/items/` y sirve contenido estático.

### Instrumentación

Se ha añadido el cliente Prometheus (`prometheus-client==0.26.0`) a
`requirements.txt` y se monta literalmente la app ASGI de métricas de
`prometheus_client` en `/metrics` **antes** del montaje catch-all de estáticos
en `/`. La ruta servida por ese montaje es `/metrics/`. La resolución del
directorio estático usa `Path(__file__)` para no depender del directorio de
trabajo.

`app_map/main.py`:

```python
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from prometheus_client import make_asgi_app

from .api.endpoints import router as item_router

app = FastAPI()

app.include_router(item_router)

metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# Resolve the statics directory relative to this file so it does not depend on
# the current working directory from which Uvicorn is launched.
statics_dir = Path(__file__).resolve().parent / "statics"
app.mount("/", StaticFiles(directory=str(statics_dir), html=True), name="static")
```

No se añaden métricas de negocio personalizadas: el ejercicio pide métricas por
defecto, y `prometheus_client` ya exporta métricas por defecto de proceso/GC/
plataforma (p. ej. `process_resident_memory_bytes`, `process_cpu_seconds_total`).

### Contenerización

`app_map/Dockerfile` usa `python:3.12-slim`, copia `requirements.txt`, instala
sin caché, copia `app_map` y arranca **Uvicorn** (no el dev server de FastAPI)
enlazado a `0.0.0.0:8000` con **un worker**:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY app_map/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY app_map /app/app_map
EXPOSE 8000
CMD ["uvicorn", "app_map.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
```

### Compose

`05-prometheus-app/compose.yml` construye `app` (mapea `8000`) y levanta
`prometheus` (`prom/prometheus:v3.14.0`, mapea `9090`, monta
`prometheus.yml`). Comparten la red de Compose implícita.

`05-prometheus-app/prometheus.yml` hace scrape de la app vía **DNS de Docker**
`app:8000` (no `localhost:8000`), usando el path del montaje ASGI `/metrics/`:

```yaml
global:
  scrape_interval: 5s
  scrape_timeout: 3s

scrape_configs:
  - job_name: app_map
    metrics_path: /metrics/
    static_configs:
      - targets:
          - app:8000
```

### Reproducción y validación

```bash
cd 06-monitoring/solutions/monitoring-exercises/05-prometheus-app

docker compose config
docker compose build
docker compose up -d

# app responde
curl -s http://localhost:8000/api/items/

# /metrics expone métricas
curl -s http://localhost:8000/metrics/ | grep -E 'process_resident_memory_bytes|process_cpu_seconds_total'

# target UP vía API de Prometheus
curl -s "http://localhost:9090/api/v1/targets" | head -c 2000

# consultas PromQL contra el target de la app
curl -s --data-urlencode 'query=process_resident_memory_bytes{job="app_map"}' \
  http://localhost:9090/api/v1/query

curl -s --data-urlencode 'query=rate(process_cpu_seconds_total{job="app_map"}[1m])' \
  http://localhost:9090/api/v1/query
```

Salida real en `evidence/prometheus-app.txt`. El target de la app debe estar
**UP**.

### Limpieza

```bash
docker compose down
```

---

## Ejercicio 5.2 — Jaeger / HotROD

Detalles y notas de experiencia en `05-jaeger-hotrod/NOTES.md`.

Resumen del enfoque: se usa **Jaeger v2 + HotROD actuales con
OpenTelemetry/OTLP**, no la infraestructura obsoleta de Jaeger v1/OpenTracing
del tutorial de 2017.

Imágenes fijadas: `jaegertracing/jaeger:2.20.0`,
`jaegertracing/example-hotrod:2.20.0`. OTLP HTTP:
`OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318`. UI Jaeger en `16686`, HotROD
en `8080`.

### Línea base

```bash
cd 06-monitoring/solutions/monitoring-exercises/05-jaeger-hotrod
docker compose -f compose.yml up -d

# verificar UI/API de Jaeger
curl -s http://localhost:16686/api/services
# verificar HotROD
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080

# generar una ráfaga concurrente comparable (PowerShell)
$url = 'http://localhost:8080/dispatch?customer=123'
$jobs = 1..24 | ForEach-Object {
  Start-Job { param($requestUrl) Invoke-WebRequest $requestUrl } -ArgumentList $url
}
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job

# trazas en Jaeger (API)
curl -s "http://localhost:16686/api/traces?service=frontend&limit=5" | head -c 2000
```

Salida real en `evidence/jaeger-baseline.txt`.

### Configuración corregida

```bash
docker compose -f compose.fixed.yml up -d
# repetir exactamente la misma ráfaga concurrente de 24 solicitudes de baseline
$url = 'http://localhost:8080/dispatch?customer=123'
$jobs = 1..24 | ForEach-Object {
  Start-Job { param($requestUrl) Invoke-WebRequest $requestUrl } -ArgumentList $url
}
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
curl -s "http://localhost:16686/api/traces?service=frontend&limit=5" | head -c 2000
```

Banderas aplicadas: `all -D 100ms -M -W 100`.

Salida real en `evidence/jaeger-fixed.txt`.

### Limpieza

```bash
docker compose -f compose.yml down
docker compose -f compose.fixed.yml down
```

---

## Capturas recomendadas para la entrega

Para la entrega final se recomienda al alumno adjuntar capturas (no
fabricadas) de:

- Prometheus Targets mostrando UP (ej. 1 y ej. 5.1);
- Prometheus — consulta de memoria;
- Prometheus — consulta de CPU;
- app `/metrics`;
- app target UP;
- Jaeger — traza baseline;
- Jaeger — traza fixed.

Las evidencias de texto en `evidence/` son la fuente de verdad de la
ejecución; las capturas son apoyo visual para la entrega.

---

## Limpieza global

```bash
# desde cada subdirectorio
cd 06-monitoring/solutions/monitoring-exercises/01-prometheus-self   && docker compose down
cd 06-monitoring/solutions/monitoring-exercises/05-prometheus-app   && docker compose down
cd 06-monitoring/solutions/monitoring-exercises/05-jaeger-hotrod    && docker compose -f compose.yml down
cd 06-monitoring/solutions/monitoring-exercises/05-jaeger-hotrod    && docker compose -f compose.fixed.yml down
```

No se dejan contenedores/redes corriendo al terminar. No se eliminan
contenedores/imágenes/volúmenes ajenos.

---

## Versiones / reproducibilidad

- `prom/prometheus:v3.14.0`
- `jaegertracing/jaeger:2.20.0`
- `jaegertracing/example-hotrod:2.20.0`
- `python:3.12-slim` (app)
- `prometheus-client==0.26.0`

No se usa `:latest` en las imágenes de la solución.
