#!/usr/bin/env bash
# Ejercicio 1 - Monolito en memoria.
# Despliega todo-app (persistencia en memoria) + Service LoadBalancer en Minikube.
#
# Uso:
#   ./ejercicio1.sh            # despliega y valida
#   ./ejercicio1.sh --debug    # modo verbose (kubectl -v, set -x)
#   ./ejercicio1.sh cleanup    # borra solo los recursos de este ejercicio
#
# Notas:
# - Los manifests NO llevan namespace: el script los aplica en un namespace dedicado
#   (lemoncode-ej1) para que los tres ejercicios sean seguros en secuencia.
# - El modo --debug sólo altera la verbosidad, no el comportamiento funcional.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
NAMESPACE="lemoncode-ej1"
MINIKUBE_PROFILE="lemoncode-orchestration"
MANIFEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-monolith-in-mem"
EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
DEPLOYMENT="todo-app"
SERVICE="todo-app"
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
  log "Eliminando recursos del ejercicio 1 (namespace $NAMESPACE)..."
  kubectl --context "$MINIKUBE_PROFILE" delete namespace "$NAMESPACE" --ignore-not-found --wait=true
  ok "Recursos del ejercicio 1 eliminados."
}

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    cleanup) ACTION="cleanup" ;;
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

# Asegurar que minikube está arrancado
if ! minikube --profile "$MINIKUBE_PROFILE" status --format '{{.Host}}' 2>/dev/null | grep -qi running; then
  log "Minikube no está corriendo. Arrancando..."
  minikube --profile "$MINIKUBE_PROFILE" start
fi
ok "Minikube está corriendo."

if [[ "$ACTION" == "cleanup" ]]; then
  cleanup_resources
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Validar manifests (dry-run) y aplicar
# ---------------------------------------------------------------------------
log "Validando manifests (dry-run cliente)..."
kubectl --context "$MINIKUBE_PROFILE" apply --dry-run=client -f "$MANIFEST_DIR/deployment.yml" >/dev/null
kubectl --context "$MINIKUBE_PROFILE" apply --dry-run=client -f "$MANIFEST_DIR/service.yml" >/dev/null
ok "Manifests válidos."

log "Creando namespace '$NAMESPACE'..."
kubectl --context "$MINIKUBE_PROFILE" create namespace "$NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$MINIKUBE_PROFILE" apply -f - >/dev/null

log "Aplicando manifests en namespace '$NAMESPACE'..."
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/deployment.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/service.yml" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 3. Esperar a que el Deployment esté listo
# ---------------------------------------------------------------------------
log "Esperando a que el Deployment '$DEPLOYMENT' esté disponible..."
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
ok "Deployment '$DEPLOYMENT' disponible."

# ---------------------------------------------------------------------------
# 4. Estado conciso de recursos
# ---------------------------------------------------------------------------
log "Estado de recursos:"
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT"
kubectl get svc "$SERVICE" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 5. Obtener URL de acceso (LoadBalancer en Minikube)
# ---------------------------------------------------------------------------
log "Obteniendo URL de acceso del LoadBalancer..."
# Con `minikube tunnel` activo, el Service recibe una IP externa local. Evitamos
# `minikube service --url`, que puede quedarse en primer plano con el driver Docker.
EXTERNAL_IP="$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")"
APP_URL="${EXTERNAL_IP:+http://$EXTERNAL_IP}"
if [[ -z "$APP_URL" ]]; then
  warn "El LoadBalancer aún no tiene External-IP. Ejecuta 'minikube --profile $MINIKUBE_PROFILE tunnel' y reintenta."
else
  ok "URL de acceso: $APP_URL"
fi

# ---------------------------------------------------------------------------
# 6. Validación a nivel HTTP (UI/API)
# ---------------------------------------------------------------------------
if [[ -n "$APP_URL" ]]; then
  log "Validando endpoint de salud /live/ ..."
  if curl -sf "$APP_URL/live/" >/dev/null 2>&1; then
    ok "/live/ responde correctamente."
  else
    warn "/live/ no respondió como se esperaba (puede tardar unos segundos)."
  fi

  log "Validando API GET /api/ (debe devolver una lista, inicialmente vacía)..."
  API_RESP="$(curl -sf "$APP_URL/api/" 2>/dev/null || echo "ERROR")"
  if [[ "$API_RESP" == "ERROR" ]]; then
    warn "GET /api/ no respondió. Revisa los logs del pod."
  else
    ok "GET /api/ respondió: $API_RESP"
  fi

  log "Validando creación de un TODO vía POST /api/ ..."
  POST_RESP="$(curl -sf -X POST "$APP_URL/api/" \
    -H 'Content-Type: application/json' \
    -d '{"title":"Ejercicio1-K8s","completed":false,"dueDate":"2026-01-01T00:00:00.000Z"}' \
    2>/dev/null || echo "ERROR")"
  if [[ "$POST_RESP" == "ok" ]]; then
    ok "POST /api/ creó el TODO correctamente (respuesta: $POST_RESP)."
  else
    warn "POST /api/ respondió: $POST_RESP"
  fi

  log "Verificando que el TODO aparece en GET /api/ ..."
  AFTER="$(curl -sf "$APP_URL/api/" 2>/dev/null || echo "ERROR")"
  if [[ "$AFTER" != "ERROR" ]] && echo "$AFTER" | grep -q "Ejercicio1-K8s"; then
    ok "El TODO creado está presente en la API: $AFTER"
  else
    warn "No se confirmó el TODO en GET /api/: $AFTER"
  fi

  log "Validando que la UI (HTML) se sirve en / ..."
  if curl -sf "$APP_URL/" 2>/dev/null | grep -qi '<div id="root"></div>'; then
    ok "La UI se sirve correctamente (HTML con el contenedor root de React)."
  else
    warn "No se encontró el HTML esperado en /."
  fi
fi

# ---------------------------------------------------------------------------
# 7. Guardar evidencia
# ---------------------------------------------------------------------------
log "Guardando evidencia..."
mkdir -p "$EVIDENCE_DIR"
{
  echo "# Ejercicio 1 - evidencia de recursos ($(date -u +%FT%TZ))"
  echo "## Namespace: $NAMESPACE"
  echo
  echo "### kubectl get deployment"
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o wide
  echo
  echo "### kubectl get pods"
  kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o wide
  echo
  echo "### kubectl get svc"
  kubectl get svc "$SERVICE" -n "$NAMESPACE" -o wide
  echo
  echo "### URL de acceso"
  echo "$APP_URL"
  echo
  echo "### /live/"
  curl -sf "$APP_URL/live/" 2>/dev/null || echo "(sin respuesta)"
  echo
  echo "### GET /api/"
  curl -sf "$APP_URL/api/" 2>/dev/null || echo "(sin respuesta)"
} > "$EVIDENCE_DIR/ejercicio1-resources.txt"
ok "Evidencia: $EVIDENCE_DIR/ejercicio1-resources.txt"

echo
ok "Ejercicio 1 completado."
echo "  Acceso: ${APP_URL:-(ver 'minikube --profile $MINIKUBE_PROFILE service $SERVICE -n $NAMESPACE --url')}"
echo "  Limpieza: ./ejercicio1.sh cleanup"
