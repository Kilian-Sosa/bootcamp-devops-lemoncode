#!/usr/bin/env bash
# Ejercicio 2 - Monolito con PostgreSQL.
# Despliega capa de persistencia (StorageClass/PV/PVC/StatefulSet Postgres) + todo-app
# con LoadBalancer. Verifica además la persistencia tras recrear el pod de Postgres.
#
# Uso:
#   ./ejercicio2.sh            # despliega y valida
#   ./ejercicio2.sh --debug    # modo verbose
#   ./ejercicio2.sh cleanup    # borra solo los recursos de este ejercicio
#   ./ejercicio2.sh cleanup-data  # borra recursos Y destruye los datos persistentes
#
# Notas:
# - Manifests aplicados en namespace dedicado (lemoncode-ej2).
# - --debug sólo cambia verbosidad, no el comportamiento funcional.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
NAMESPACE="lemoncode-ej2"
MINIKUBE_PROFILE="lemoncode-orchestration"
MANIFEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/01-monolith"
EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
STORAGE_CLASS="postgres-storage"
PV_NAME="postgres-pv"
PVC_NAME="postgres-pvc"
PG_STATEFULSET="postgres"
PG_SERVICE="postgres"
APP_DEPLOYMENT="todo-app"
APP_SERVICE="todo-app"
DEBUG=0
ACTION="apply"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

kc() {
  if [[ "$DEBUG" -eq 1 ]]; then
    kubectl --namespace "$NAMESPACE" "$@"
  else
    kubectl --namespace "$NAMESPACE" "$@" 2>/dev/null
  fi
}

cleanup_resources() {
  log "Eliminando cargas de trabajo del ejercicio 2 (namespace $NAMESPACE)..."
  kubectl --context "$MINIKUBE_PROFILE" delete statefulset "$PG_STATEFULSET" -n "$NAMESPACE" --ignore-not-found --wait=true
  kubectl --context "$MINIKUBE_PROFILE" delete deployment "$APP_DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found --wait=true
  kubectl --context "$MINIKUBE_PROFILE" delete service "$PG_SERVICE" "$APP_SERVICE" -n "$NAMESPACE" --ignore-not-found --wait=true
  kubectl --context "$MINIKUBE_PROFILE" delete configmap postgres-config todo-app-config -n "$NAMESPACE" --ignore-not-found --wait=true
  ok "Cargas de trabajo eliminadas; namespace y almacenamiento conservados."
}

cleanup_data() {
  log "Destruyendo los datos persistentes del ejercicio 2..."
  kubectl --context "$MINIKUBE_PROFILE" delete pvc "$PVC_NAME" -n "$NAMESPACE" --ignore-not-found --wait=true
  kubectl --context "$MINIKUBE_PROFILE" delete pv "$PV_NAME" --ignore-not-found --wait=true
  kubectl --context "$MINIKUBE_PROFILE" delete storageclass "$STORAGE_CLASS" --ignore-not-found --wait=true
  minikube --profile "$MINIKUBE_PROFILE" ssh "sudo rm -rf -- /mnt/data/lemoncode-postgres"
  ok "PVC, PV, StorageClass y datos hostPath del ejercicio eliminados."
}

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    cleanup) ACTION="cleanup" ;;
    cleanup-data) ACTION="cleanup-data" ;;
    *) err "Argumento no reconocido: $arg"; exit 2 ;;
  esac
done

if [[ "$DEBUG" -eq 1 ]]; then
  set -x
fi

# ---------------------------------------------------------------------------
# 1. Validar herramientas y contexto
# ---------------------------------------------------------------------------
log "Validando herramientas y contexto..."

for tool in kubectl minikube curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    err "No se encontró '$tool'. Es necesario para este ejercicio."
    exit 1
  fi
done

CURRENT_CTX="$(kubectl config current-context 2>/dev/null || echo "")"
if [[ "$CURRENT_CTX" != "$MINIKUBE_PROFILE" ]]; then
  warn "El contexto actual de kubectl es '$CURRENT_CTX', no '$MINIKUBE_PROFILE'."
  warn "Este ejercicio está pensado para el perfil Minikube aprobado. Se aborta para evitar aplicar"
  warn "recursos de formación en un clúster ajeno."
  err "Ejecuta 'kubectl config use-context $MINIKUBE_PROFILE' y reintenta."
  exit 1
fi
ok "Contexto kubectl: $CURRENT_CTX"

if ! minikube --profile "$MINIKUBE_PROFILE" status --format '{{.Host}}' 2>/dev/null | grep -qi running; then
  log "Minikube no está corriendo. Arrancando..."
  minikube --profile "$MINIKUBE_PROFILE" start
fi
ok "Minikube está corriendo."

if [[ "$ACTION" == "cleanup" ]]; then
  cleanup_resources
  exit 0
fi

if [[ "$ACTION" == "cleanup-data" ]]; then
  cleanup_resources
  cleanup_data
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Validar manifests (dry-run)
# ---------------------------------------------------------------------------
log "Validando manifests (dry-run cliente)..."
for f in postgres-configmap storageclass persistentvolume persistentvolumeclaim \
         postgres-service postgres-statefulset todo-configmap todo-deployment todo-service; do
  kubectl --context "$MINIKUBE_PROFILE" apply --dry-run=client -f "$MANIFEST_DIR/$f.yml" >/dev/null
done
ok "Manifests válidos."

log "Creando namespace '$NAMESPACE'..."
kubectl --context "$MINIKUBE_PROFILE" create namespace "$NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$MINIKUBE_PROFILE" apply -f - >/dev/null

# ---------------------------------------------------------------------------
# 3. Asegurar que el directorio hostPath existe en el nodo Minikube
# ---------------------------------------------------------------------------
log "Asegurando directorio hostPath en el nodo Minikube..."
minikube --profile "$MINIKUBE_PROFILE" ssh "sudo mkdir -p /mnt/data/lemoncode-postgres" 2>/dev/null || \
  warn "No se pudo crear el directorio via minikube ssh (el PV lo crea con DirectoryOrCreate)."

# ---------------------------------------------------------------------------
# 4. Aplicar recursos de almacenamiento/config/DB (orden sensato)
# ---------------------------------------------------------------------------
log "Aplicando StorageClass, PV, PVC y config de Postgres..."
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/storageclass.yml"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/persistentvolume.yml"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/persistentvolumeclaim.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/postgres-configmap.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/postgres-service.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/postgres-statefulset.yml" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 5. Esperar a que el PVC quede Bound
# ---------------------------------------------------------------------------
log "Esperando a que el PVC '$PVC_NAME' quede Bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  "pvc/$PVC_NAME" -n "$NAMESPACE" --timeout=120s
ok "PVC '$PVC_NAME' está Bound."

log "Estado de almacenamiento:"
kubectl get sc "$STORAGE_CLASS"
kubectl get pv "$PV_NAME"
kubectl get pvc "$PVC_NAME" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 6. Esperar a que PostgreSQL esté listo
# ---------------------------------------------------------------------------
log "Esperando a que el StatefulSet '$PG_STATEFULSET' esté listo..."
kubectl rollout status "statefulset/$PG_STATEFULSET" -n "$NAMESPACE" --timeout=300s
ok "PostgreSQL está listo."

# Verificar que el pod está listo
PG_POD="$(kubectl get pods -n "$NAMESPACE" -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
if [[ -z "$PG_POD" ]]; then
  err "No se encontró el pod de PostgreSQL."
  exit 1
fi
ok "Pod de PostgreSQL: $PG_POD"

# ---------------------------------------------------------------------------
# 7. Verificar que la BD y el esquema existen (seed de la imagen cocinada)
# ---------------------------------------------------------------------------
log "Verificando que la BD 'todos_db' y la tabla 'todos' existen..."
# psql dentro del pod: listamos la BD y contamos filas de todos.
DB_CHECK="$(kubectl exec "$PG_POD" -n "$NAMESPACE" -- \
  psql -U postgres -d todos_db -t -c "SELECT count(*) FROM todos;" 2>/dev/null || echo "ERROR")"
if [[ "$DB_CHECK" == "ERROR" ]] || [[ -z "$DB_CHECK" ]]; then
  warn "No se pudo consultar la tabla todos. Puede que el seed aún se esté ejecutando."
  warn "Reintentando en 10s..."
  sleep 10
  DB_CHECK="$(kubectl exec "$PG_POD" -n "$NAMESPACE" -- \
    psql -U postgres -d todos_db -t -c "SELECT count(*) FROM todos;" 2>/dev/null || echo "ERROR")"
fi
if [[ "$DB_CHECK" != "ERROR" ]] && [[ -n "$DB_CHECK" ]]; then
  ok "La BD 'todos_db' está inicializada. Filas en 'todos': $(echo "$DB_CHECK" | tr -d '[:space:]')"
else
  err "No se pudo inicializar/verificar la base de datos. Revisa los logs del pod de Postgres."
  kubectl logs "$PG_POD" -n "$NAMESPACE" | tail -40 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 8. Aplicar recursos de todo-app
# ---------------------------------------------------------------------------
log "Aplicando ConfigMap, Deployment y Service de todo-app..."
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-configmap.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-deployment.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-service.yml" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 9. Esperar a que todo-app esté listo
# ---------------------------------------------------------------------------
log "Esperando a que el Deployment '$APP_DEPLOYMENT' esté disponible..."
kubectl rollout status "deployment/$APP_DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
ok "todo-app '$APP_DEPLOYMENT' está disponible."

# ---------------------------------------------------------------------------
# 10. Estado conciso
# ---------------------------------------------------------------------------
log "Estado de recursos:"
kubectl get statefulset "$PG_STATEFULSET" -n "$NAMESPACE"
kubectl get deployment "$APP_DEPLOYMENT" -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -o wide
kubectl get svc -n "$NAMESPACE"
kubectl get pv "$PV_NAME"
kubectl get pvc "$PVC_NAME" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 11. Obtener URL de acceso y validar app/API
# ---------------------------------------------------------------------------
log "Obteniendo URL de acceso (minikube service)..."
APP_URL="$(minikube --profile "$MINIKUBE_PROFILE" service "$APP_SERVICE" -n "$NAMESPACE" --url 2>/dev/null || echo "")"
if [[ -n "$APP_URL" ]]; then
  ok "URL de acceso: $APP_URL"

  log "Validando /live/ de todo-app..."
  if curl -sf "$APP_URL/live/" >/dev/null 2>&1; then
    ok "/live/ responde."
  else
    warn "/live/ no respondió (puede tardar). Revisa 'kubectl logs'."
  fi

  log "Validando GET /api/ (debe devolver los TODOS sembrados por la BD)..."
  API_RESP="$(curl -sf "$APP_URL/api/" 2>/dev/null || echo "ERROR")"
  if [[ "$API_RESP" != "ERROR" ]]; then
    ok "GET /api/ respondió: $API_RESP"
  else
    warn "GET /api/ no respondió. Revisa logs de todo-app y conectividad con Postgres."
    kubectl logs -n "$NAMESPACE" -l app="$APP_DEPLOYMENT" --tail=40 || true
  fi
else
  warn "No se pudo obtener la URL. Usa: minikube --profile $MINIKUBE_PROFILE service $APP_SERVICE -n $NAMESPACE --url"
fi

# ---------------------------------------------------------------------------
# 12. Validación de PERSISTENCIA (núcleo del ejercicio)
# ---------------------------------------------------------------------------
if [[ -n "$APP_URL" ]]; then
  log "=== Validación de persistencia ==="

  # 12a. Crear un TODO de control a través de la app (escribe en Postgres).
  log "Creando TODO de control para la prueba de persistencia..."
  curl -sf -X POST "$APP_URL/api/" \
    -H 'Content-Type: application/json' \
    -d '{"title":"Persist-K8s-Ej2","completed":false,"dueDate":"2026-01-01T00:00:00.000Z"}' \
    >/dev/null 2>&1 || warn "POST no completado (continuando)."

  log "TODOs actuales vía API antes de recrear Postgres:"
  BEFORE="$(curl -sf "$APP_URL/api/" 2>/dev/null || echo "ERROR")"
  ok "Antes: $BEFORE"

  # 12b. Recrear el pod de Postgres SIN borrar PVC/PV.
  log "Recreando el pod de PostgreSQL (sin tocar PVC/PV)..."
  kubectl --context "$MINIKUBE_PROFILE" delete pod "$PG_POD" -n "$NAMESPACE" --wait=true

  # Esperar a que el nuevo pod esté listo.
  log "Esperando a que el nuevo pod de PostgreSQL esté listo..."
  kubectl rollout status "statefulset/$PG_STATEFULSET" -n "$NAMESPACE" --timeout=300s

  # Recrear también el pod de todo-app para que reabra la conexión Knex con Postgres
  # (la conexión se abre al arrancar el proceso y puede quedar rota tras el reinicio
  # de la BD). No afecta a la persistencia: los datos viven en Postgres, no en la app.
  log "Recreando el pod de todo-app para reabrir la conexión con Postgres..."
  APP_POD="$(kubectl get pods -n "$NAMESPACE" -l app="$APP_DEPLOYMENT" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
  if [[ -n "$APP_POD" ]]; then
    kubectl --context "$MINIKUBE_PROFILE" delete pod "$APP_POD" -n "$NAMESPACE" --wait=true
    kubectl rollout status "deployment/$APP_DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
  fi

  # Esperar a que la app vuelva a poder servir.
  log "Esperando a que todo-app vuelva a servir..."
  for _ in $(seq 1 30); do
    if curl -sf "$APP_URL/live/" >/dev/null 2>&1; then break; fi
    sleep 2
  done

  # 12c. Verificar que el TODO de control sigue existiendo.
  log "Consultando TODOs vía API después de recrear Postgres..."
  AFTER="$(curl -sf "$APP_URL/api/" 2>/dev/null || echo "ERROR")"
  ok "Después: $AFTER"

  if [[ "$AFTER" != "ERROR" ]] && echo "$AFTER" | grep -q "Persist-K8s-Ej2"; then
    ok "PERSISTENCIA VERIFICADA: el TODO de control sobrevive a la recreación del pod de Postgres."
  else
    warn "No se confirmó el TODO de control tras recrear el pod."
    warn "Verifica manualmente que el PVC sigue Bound y no se borró."
  fi

  # Verificación directa en la BD.
  log "Verificación directa en PostgreSQL del TODO de control..."
  PG_CHECK="$(kubectl exec -n "$NAMESPACE" "$PG_STATEFULSET-0" -- \
    psql -U postgres -d todos_db -t -c \
    "SELECT count(*) FROM todos WHERE title='Persist-K8s-Ej2';" 2>/dev/null || echo "ERROR")"
  if [[ "$PG_CHECK" != "ERROR" ]] && [[ -n "$PG_CHECK" ]]; then
    ok "PostgreSQL confirma el TODO de control: $(echo "$PG_CHECK" | tr -d '[:space:]') fila(s)."
  else
    warn "No se pudo verificar directamente en PostgreSQL."
  fi
fi

# ---------------------------------------------------------------------------
# 13. Guardar evidencia
# ---------------------------------------------------------------------------
log "Guardando evidencia..."
mkdir -p "$EVIDENCE_DIR"
{
  echo "# Ejercicio 2 - evidencia de recursos ($(date -u +%FT%TZ))"
  echo "## Namespace: $NAMESPACE"
  echo
  echo "### StorageClass"
  kubectl get sc "$STORAGE_CLASS" -o wide
  echo
  echo "### PersistentVolume"
  kubectl get pv "$PV_NAME" -o wide
  echo
  echo "### PersistentVolumeClaim"
  kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o wide
  echo
  echo "### StatefulSet / Deployment / Pods / Services"
  kubectl get statefulset "$PG_STATEFULSET" -n "$NAMESPACE" -o wide
  echo
  kubectl get deployment "$APP_DEPLOYMENT" -n "$NAMESPACE" -o wide
  echo
  kubectl get pods -n "$NAMESPACE" -o wide
  echo
  kubectl get svc -n "$NAMESPACE" -o wide
  echo
  echo "### URL de acceso"
  echo "$APP_URL"
  echo
  echo "### GET /api/ (respuesta de la app)"
  curl -sf "$APP_URL/api/" 2>/dev/null || echo "(sin respuesta)"
  echo
  echo "### Conteo de filas en todos (psql directo)"
  kubectl exec -n "$NAMESPACE" "$PG_STATEFULSET-0" -- psql -U postgres -d todos_db -t -c "SELECT count(*) FROM todos;" 2>/dev/null || echo "(error)"
} > "$EVIDENCE_DIR/ejercicio2-resources.txt"
ok "Evidencia: $EVIDENCE_DIR/ejercicio2-resources.txt"

# Guardar evidencia de almacenamiento por separado.
{
  echo "# Ejercicio 2 - evidencia de almacenamiento ($(date -u +%FT%TZ))"
  kubectl get sc
  echo
  kubectl get pv
  echo
  kubectl get pvc -n "$NAMESPACE"
} > "$EVIDENCE_DIR/ejercicio2-storage.txt"
ok "Evidencia de almacenamiento: $EVIDENCE_DIR/ejercicio2-storage.txt"

echo
ok "Ejercicio 2 completado."
echo "  Acceso: ${APP_URL:-(ver 'minikube --profile $MINIKUBE_PROFILE service $APP_SERVICE -n $NAMESPACE --url')}"
echo "  Limpieza (conserva datos): ./ejercicio2.sh cleanup"
echo "  Limpieza (destruye datos):  ./ejercicio2.sh cleanup-data"
