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

Tráfico generado: ráfaga de **24 peticiones concurrentes** desde PowerShell:

```powershell
$url = 'http://localhost:8080/dispatch?customer=123'
$jobs = 1..24 | ForEach-Object {
  Start-Job { param($requestUrl) Invoke-WebRequest $requestUrl } -ArgumentList $url
}
$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

Observaciones reales capturadas en `evidence/jaeger-baseline.txt`.

Observaciones (2026-08-27):

- 24/24 respuestas HTTP 200; latencia de cliente: mínimo 728 ms, mediana
  3138 ms y máximo 5156.5 ms.
- Traza de ejemplo: `7164652cad5eceba8e80429013e41860`.
- Los spans `SQL SELECT` estuvieron entre 275623 y 4692875 microsegundos.
  El máximo muestra que el retardo artificial de 300 ms se acumula bajo carga.
- Los logs de esos spans incluyen `Acquired lock; N transactions waiting
  behind`, con `N` máximo de 14: es evidencia directa de serialización por el
  mutex de conexión de BD.
- La concurrencia máxima calculada a partir de los intervalos de los spans
  `GET /route` fue 3, coherente con el pool de workers por defecto.

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

Se aplicó exactamente la misma ráfaga de 24 peticiones concurrentes.

- 22/24 respuestas HTTP 200; latencia de cliente: mínimo 349.7 ms, mediana
  463.6 ms y máximo 661.4 ms. Las dos respuestas no exitosas se corresponden
  con `redis timeout` del simulador HotROD tras tres reintentos; se conservan
  como evidencia y no se atribuyen al cambio de BD o de route.
- Traza de ejemplo: `4a60d3a8f2f88f8dd70778afb72b750a`.
- Los spans `SQL SELECT` estuvieron entre 49769 y 191360 microsegundos. No se
  registraron eventos `Acquired lock`, consistente con `-M` desactivando el
  mutex de conexión.
- La concurrencia máxima calculada para `GET /route` fue 20. Los spans se
  solapan ampliamente, frente al máximo de 3 de baseline, demostrando el
  efecto de `-W 100`.

## 7. Experiencia

La ráfaga concurrente hizo visibles los problemas que una petición aislada no
muestra: en baseline la espera de mutex llegó a 14 transacciones y route no
superó tres spans simultáneos. Tras aplicar las correcciones, la mediana de la
ráfaga bajó de 3138 ms a 463.6 ms, los spans MySQL dejaron de acumular segundos
de espera y route alcanzó 20 spans simultáneos. El tracing permite atribuir la
mejora a los cuellos de botella concretos, no solo observar que el tiempo total
ha cambiado.

---

> Estado de ejecución: baseline y fixed se ejecutaron localmente el
> 2026-08-27. Las observaciones anteriores y los ficheros de `evidence/` se
> derivan de esas ejecuciones.
