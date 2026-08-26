# Notas — Ejercicio 5.2: Jaeger / HotROD

> Nota sobre la modernización: el tutorial original de HotROD (2017) usaba
> OpenTracing, Jaeger v1 (all-in-one) y el agente Jaeger por UDP en el puerto
> 6831. Jaeger v1 está EOL (end of life). Aquí usamos **Jaeger v2** y
> **HotROD** actual, que emite trazas con **OpenTelemetry** y las envía por
> **OTLP/HTTP** (`OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318`). No se
> recrea infraestructura obsoleta de Jaeger v1/OpenTracing.

Imágenes fijadas:

- `jaegertracing/jaeger:2.20.0`
- `jaegertracing/example-hotrod:2.20.0`

---

## 1. Edad del tutorial / modernización

El tutorial original de 2017 es de la era **OpenTracing** y usaba el patrón
all-in-one de Jaeger v1 con el agente UDP en `6831`. El demo actual (2.20.0)
está instrumentado con **OpenTelemetry** y envía por OTLP. Jaeger v2 ya no usa
el agente UDP para recolección; recibe por OTLP (HTTP `4318` o gRPC `4317`) y
expone la UI en `16686`. Por tanto se sigue el *concepto* del tutorial
(investigar cuellos de botella con trazas y aplicar las correcciones) pero con
el stack actual.

## 2. Línea base (baseline)

Comando de arranque:

```bash
docker compose -f compose.yml up -d
```

Clientes de ejemplo válidos: `123`, `392`, `731`, `567`.
Endpoint de despacho: `GET /dispatch?customer=<ID>`.

Tráfico generado (varias peticiones, algunas concurrentes):

```bash
for i in 1 2 3 4 5 6 7 8; do
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" \
    "http://localhost:8080/dispatch?customer=$((RANDOM % 4 == 0 ? 123 : 392))"
done
```

Observaciones reales capturadas en `evidence/jaeger-baseline.txt`.

<!-- BASELINE-OBSERVATIONS: se rellenará tras la ejecución real -->

## 3. Retardo de BD (`-D` / `--fix-db-query-delay`)

En la línea base el servicio de BD simula una consulta MySQL lenta con una
latencia artificial elevada. La bandera `-D <duration>` reduce ese retardo de
consulta. En las trazas se manifiesta como el span del servicio de base de
datos con una duración menor; los spans descendientes de la ruta de cliente
dejan de esperar tanto en la BD.

## 4. Mutex de conexión a BD (`-M` / `--fix-disable-db-conn-mutex`)

En la línea base existe un mutex / *pool de conexiones de tamaño uno* en el
servicio de BD, de modo que bajo carga concurrente varias peticiones se
serializan esperando esa única conexión. `-M` desactiva ese mutex, permitiendo
que varias consultas a BD se sirvan en paralelo. Bajo carga concurrente el
efecto se nota en menos *queueing* y en spans de BD solapados en vez de
estrictamente secuenciales.

## 5. Pool de workers de route (`-W` / `--fix-route-worker-pool-size`)

En la línea base el servicio de ruta (`route`) tiene un *worker pool* muy
pequeño, lo que limita la concurrencia: varias peticiones de ruta se
encolan y se procesan casi de una en una. `-W <n>` amplía ese pool. Con un
pool mayor, las llamadas al servicio de ruta se vuelven más paralelas: en las
trazas aparecen spans `route` solapados en el tiempo en lugar de encolados.

## 6. Configuración corregida (fixed)

```bash
docker compose -f compose.fixed.yml up -d
```

Banderas aplicadas: `all -D 100ms -M -W 100`.

Observaciones reales capturadas en `evidence/jaeger-fixed.txt`.

<!-- FIXED-OBSERVATIONS: se rellenará tras la ejecución real -->

## 7. Experiencia

<!-- EXPERIENCE: se rellenará tras la ejecución real -->

> Lo que el tracing distribuido facilita: mirando solo el tiempo de respuesta
> agregado o los logs, un cuello de botella se percibe como "todo va lento",
> pero no se sabe *dónde*. Con trazas se ve la jerarquía de spans de una petición
> concreta y se puede identificar de forma directa cuál servicio (BD, ruta,
> cliente) consume la mayor parte de la latencia, y si los spans de un mismo
> servicio se solapan o se encolan. Eso convierte el análisis de causa raíz en
> algo mucho más dirigido que inferir a partir de métricas agregadas.

---

> Estado de ejecución: los bloques marcados como pendientes se rellenarán con
> observaciones reales tras la ejecución local. No se inventan mediciones.
