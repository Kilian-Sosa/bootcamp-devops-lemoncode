#!/usr/bin/env bash
# Ejercicio 3 - Aplicación distribuida (frontend + API) con Ingress.
# Despliega todo-front (ClusterIP), todo-api (ClusterIP) y un Ingress que expone
# ambos servicios en el mismo origen público: /  -> front, /api -> api (sin rewrite).
#
# Uso:
#   ./ejercicio3.sh            # despliega y valida
#   ./ejercicio3.sh --debug    # modo verbose
#   ./ejercicio3.sh cleanup    # borra solo los recursos de este ejercicio
#
# Notas:
# - Manifests aplicados en namespace dedicado (lemoncode-ej3).
# - --debug sólo cambia verbosidad, no el comportamiento funcional.

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
NAMESPACE="lemoncode-ej3"
MINIKUBE_PROFILE="lemoncode-orchestration"
MANIFEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/02-distributed"
EVIDENCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/evidence"
FRONT_DEPLOYMENT="todo-front"
API_DEPLOYMENT="todo-api"
INGRESS_NAME="todo-ingress"
DEBUG=0
ACTION="apply"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

cleanup_resources() {
  log "Eliminando recursos del ejercicio 3 (namespace $NAMESPACE)..."
  kubectl --context "$MINIKUBE_PROFILE" delete namespace "$NAMESPACE" --ignore-not-found --wait=true
  # El Ingress vive dentro del namespace, así que al borrar el namespace se elimina.
  ok "Recursos del ejercicio 3 eliminados."
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
# 2. Asegurar/verificar el addon de Ingress y su controlador
# ---------------------------------------------------------------------------
log "Verificando/activando el addon 'ingress' de Minikube..."
if ! minikube --profile "$MINIKUBE_PROFILE" addons list 2>/dev/null | grep -qE '^\| ingress\s+\| Enabled'; then
  log "Activando addon ingress..."
  minikube --profile "$MINIKUBE_PROFILE" addons enable ingress
fi
ok "Addon ingress habilitado."

# Esperar a que exista un IngressController / pods del controlador listos.
log "Esperando al controlador de Ingress (namespace ingress-nginx)..."
# El addon de Minikube crea el namespace ingress-nginx con el controlador.
for _ in $(seq 1 60); do
  if kubectl get namespace ingress-nginx >/dev/null 2>&1; then break; fi
  sleep 2
done
if ! kubectl get namespace ingress-nginx >/dev/null 2>&1; then
  err "El namespace 'ingress-nginx' no existe. El addon de ingress no se instaló."
  exit 1
fi

for _ in $(seq 1 60); do
  READY="$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "")"
  if [[ "$READY" == "true" ]]; then break; fi
  sleep 2
done
if [[ "$READY" != "true" ]]; then
  warn "El controlador de Ingress no está completamente listo todavía."
  warn "Se continúa, pero la validación HTTP podría fallar si tarda en arrancar."
else
  ok "Controlador de Ingress listo."
fi

# Determinar el IngressClass a usar. Minikube instala la clase "nginx".
INGRESS_CLASS="nginx"
if ! kubectl get ingressclass "$INGRESS_CLASS" >/dev/null 2>&1; then
  # Intentar detectar la clase disponible.
  DETECTED="$(kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"
  if [[ -n "$DETECTED" ]]; then
    INGRESS_CLASS="$DETECTED"
    warn "No se encontró la IngressClass 'nginx'; se usará '$INGRESS_CLASS'."
  else
    err "No se encontró ninguna IngressClass. Activa el addon ingress de Minikube."
    exit 1
  fi
fi
ok "IngressClass en uso: $INGRESS_CLASS"

# ---------------------------------------------------------------------------
# 3. Validar manifests (dry-run)
# ---------------------------------------------------------------------------
log "Validando manifests (dry-run cliente)..."
for f in todo-front-deployment todo-front-service todo-api-configmap \
         todo-api-deployment todo-api-service ingress; do
  kubectl --context "$MINIKUBE_PROFILE" apply --dry-run=client -f "$MANIFEST_DIR/$f.yml" >/dev/null
done
ok "Manifests válidos."

log "Creando namespace '$NAMESPACE'..."
kubectl --context "$MINIKUBE_PROFILE" create namespace "$NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$MINIKUBE_PROFILE" apply -f - >/dev/null

# ---------------------------------------------------------------------------
# 4. Aplicar frontend y API
# ---------------------------------------------------------------------------
log "Aplicando ConfigMap, Deployments y Services de front y API..."
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-api-configmap.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-api-deployment.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-api-service.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-front-deployment.yml" -n "$NAMESPACE"
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/todo-front-service.yml" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 5. Esperar a que ambos Deployments estén listos
# ---------------------------------------------------------------------------
log "Esperando a que el Deployment '$FRONT_DEPLOYMENT' esté disponible..."
kubectl rollout status "deployment/$FRONT_DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
log "Esperando a que el Deployment '$API_DEPLOYMENT' esté disponible..."
kubectl rollout status "deployment/$API_DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
ok "Ambos Deployments disponibles."

# ---------------------------------------------------------------------------
# 6. Aplicar Ingress (y esperar a que adquiera un backend/IngressClass)
# ---------------------------------------------------------------------------
log "Aplicando Ingress..."
kubectl --context "$MINIKUBE_PROFILE" apply -f "$MANIFEST_DIR/ingress.yml" -n "$NAMESPACE"

log "Esperando a que el Ingress adquiera una IP asignada..."
for _ in $(seq 1 60); do
  ADDR="$(kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")"
  [[ -n "$ADDR" && "$ADDR" != "" ]] && break
  # En Minikube con ingress, a veces no se rellena .status.loadBalancer.ingress;
  # se usa la IP del nodo.
  sleep 2
done

# Resolver la IP de acceso: si el Ingress no tiene IP asignada, usar la IP del nodo Minikube.
MINIKUBE_IP="$(minikube --profile "$MINIKUBE_PROFILE" ip 2>/dev/null || echo "")"
if [[ -n "$ADDR" ]]; then
  ACCESS_IP="$ADDR"
elif [[ -n "$MINIKUBE_IP" ]]; then
  ACCESS_IP="$MINIKUBE_IP"
  warn "El Ingress no reporta IP en .status.loadBalancer; se usará la IP del nodo Minikube: $ACCESS_IP"
else
  ACCESS_IP=""
  warn "No se pudo determinar la IP de acceso."
fi

if [[ -n "$ACCESS_IP" ]]; then
  ok "IP/host de acceso: $ACCESS_IP"
fi

# ---------------------------------------------------------------------------
# 7. Estado conciso
# ---------------------------------------------------------------------------
log "Estado de recursos:"
kubectl get deployment "$FRONT_DEPLOYMENT" -n "$NAMESPACE"
kubectl get deployment "$API_DEPLOYMENT" -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -o wide
kubectl get svc -n "$NAMESPACE"
kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE"

# ---------------------------------------------------------------------------
# 8. Validación HTTP (frontend y API vía Ingress, mismo origen)
# ---------------------------------------------------------------------------
if [[ -n "$ACCESS_IP" ]]; then
  # Añadir resolución temporal del host en /etc/hosts no es necesario: el Ingress
  # usa un rule sin host (sólo path), así que podemos hacer peticiones directas a la IP.
  BASE_URL="http://$ACCESS_IP"

  log "Validando acceso al frontend vía Ingress (GET /)..."
  FRONT_HTML="$(curl -sf "$BASE_URL/" 2>/dev/null || echo "ERROR")"
  if [[ "$FRONT_HTML" != "ERROR" ]] && echo "$FRONT_HTML" | grep -qi "Todos App"; then
    ok "Frontend servido correctamente vía Ingress (HTML con 'Todos App')."
  elif [[ "$FRONT_HTML" != "ERROR" ]]; then
    ok "Frontend responde vía Ingress (HTML recibido)."
  else
    warn "El frontend no respondió vía Ingress. Puede que el controlador tarde en propagar."
  fi

  log "Validando API vía Ingress (GET /api/, mismo origen)..."
  API_RESP="$(curl -sf "$BASE_URL/api/" 2>/dev/null || echo "ERROR")"
  if [[ "$API_RESP" != "ERROR" ]]; then
    ok "API responde vía Ingress (GET /api/): $API_RESP"
  else
    warn "GET /api/ no respondió vía Ingress. Revisa el controlador y los servicios."
  fi

  # 9. Verificar que el frontend carga y usa datos de la API (mismo origen).
  log "Verificando integración frontend/API (crear + leer vía Ingress)..."
  POST_RESP="$(curl -sf -X POST "$BASE_URL/api/" \
    -H 'Content-Type: application/json' \
    -d '{"title":"Ej3-Ingress","completed":false,"dueDate":"2026-01-01T00:00:00.000Z"}' \
    2>/dev/null || echo "ERROR")"
  if [[ "$POST_RESP" == "ok" ]]; then
    ok "POST /api/ vía Ingress creó un TODO (respuesta: $POST_RESP)."
  else
    warn "POST /api/ vía Ingress respondió: $POST_RESP"
  fi

  AFTER="$(curl -sf "$BASE_URL/api/" 2>/dev/null || echo "ERROR")"
  if [[ "$AFTER" != "ERROR" ]] && echo "$AFTER" | grep -q "Ej3-Ingress"; then
    ok "El frontend puede leer los TODOS de la API vía Ingress (mismo origen): $AFTER"
  else
    warn "No se confirmó el TODO vía Ingress: $AFTER"
  fi

  log "Verificando que los assets del frontend (JS) se sirven vía Ingress..."
  # El HTML de webpack incluye un bundle JS con hash. Comprobamos que responde 200.
  JS_PATH="$(echo "$FRONT_HTML" | grep -oE 'src="[^"]+\.js"' | sed 's/src="//;s/"//' | head -1 || echo "")"
  if [[ -n "$JS_PATH" ]]; then
    # Normalizar a ruta absoluta relativa al host.
    case "$JS_PATH" in
      http*) JS_URL="$JS_PATH" ;;
      /*)    JS_URL="$BASE_URL$JS_PATH" ;;
      *)     JS_URL="$BASE_URL/$JS_PATH" ;;
    esac
    if curl -sf -o /dev/null "$JS_URL" 2>/dev/null; then
      ok "Asset JS del frontend accesible vía Ingress: $JS_URL"
    else
      warn "Asset JS no accesible: $JS_URL"
    fi
  else
    warn "No se detectó bundle JS en el HTML del frontend."
  fi
fi

# ---------------------------------------------------------------------------
# 10. Guardar evidencia
# ---------------------------------------------------------------------------
log "Guardando evidencia..."
mkdir -p "$EVIDENCE_DIR"
{
  echo "# Ejercicio 3 - evidencia de recursos ($(date -u +%FT%TZ))"
  echo "## Namespace: $NAMESPACE"
  echo
  echo "### Deployments"
  kubectl get deployment "$FRONT_DEPLOYMENT" -n "$NAMESPACE" -o wide
  echo
  kubectl get deployment "$API_DEPLOYMENT" -n "$NAMESPACE" -o wide
  echo
  echo "### Pods"
  kubectl get pods -n "$NAMESPACE" -o wide
  echo
  echo "### Services"
  kubectl get svc -n "$NAMESPACE" -o wide
  echo
  echo "### Ingress"
  kubectl get ingress "$INGRESS_NAME" -n "$NAMESPACE" -o wide
  echo
  kubectl describe ingress "$INGRESS_NAME" -n "$NAMESPACE"
  echo
  echo "### IngressClass"
  kubectl get ingressclass "$INGRESS_CLASS" -o wide
  echo
  echo "### IP de acceso"
  echo "$ACCESS_IP"
  echo
  echo "### GET / (frontend) primeras líneas"
  curl -sf "http://$ACCESS_IP/" 2>/dev/null | head -20 || echo "(sin respuesta)"
  echo
  echo "### GET /api/ (API vía Ingress)"
  curl -sf "http://$ACCESS_IP/api/" 2>/dev/null || echo "(sin respuesta)"
} > "$EVIDENCE_DIR/ejercicio3-resources.txt"
ok "Evidencia: $EVIDENCE_DIR/ejercicio3-resources.txt"

# Evidencia de Ingress por separado.
{
  echo "# Ejercicio 3 - evidencia de Ingress ($(date -u +%FT%TZ))"
  kubectl get ingress -n "$NAMESPACE"
  echo
  kubectl describe ingress "$INGRESS_NAME" -n "$NAMESPACE"
  echo
  kubectl get ingressclass
} > "$EVIDENCE_DIR/ejercicio3-ingress.txt"
ok "Evidencia de Ingress: $EVIDENCE_DIR/ejercicio3-ingress.txt"

echo
ok "Ejercicio 3 completado."
if [[ -n "$ACCESS_IP" ]]; then
  echo "  Acceso: http://$ACCESS_IP  (frontend: / , API: /api/)"
fi
echo "  Limpieza: ./ejercicio3.sh cleanup"
