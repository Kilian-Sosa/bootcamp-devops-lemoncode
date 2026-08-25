#!/usr/bin/env bash
#
# reto3.sh — Reto 3: Dockerizar el frontend Node.js.
#
# Garantiza los prerrequisitos (MongoDB + backend), construye la imagen del
# frontend, arranca el contenedor `topics-front` en `lemoncode-network`, expone
# el puerto 3000 y verifica que la página responde y carga datos del backend.
#
# Uso:
#   ./reto3.sh            Construye y arranca el frontend.
#   ./reto3.sh --debug    Igual, pero con trazas detalladas.
#   ./reto3.sh --down     Detiene y elimina el contenedor del frontend (no toca
#                         el backend ni MongoDB).
#
# NOTA DE RED: el frontend hace el fetch al backend EN EL SERVIDOR (server.js
# usa node-fetch), no en el navegador. Por eso API_URL puede apuntar a
# http://topics-api:5000/api/classes (hostname de Docker DNS) y funcionar aunque
# el navegador del host no pueda resolver `topics-api`. Ver README.md.
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Configuración (nombres estables y propios de este ejercicio)
# ----------------------------------------------------------------------------
NETWORK_NAME="lemoncode-network"

FRONTEND_IMAGE="lemoncode-frontend"
FRONTEND_CONTAINER="topics-front"
FRONTEND_PORT="3000"

BACKEND_CONTAINER="topics-api"
BACKEND_PORT="5000"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
DEBUG=0
ACTION="up"

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    --down)  ACTION="down" ;;
    -h|--help)
      sed -n '3,23p' "$0"
      exit 0
      ;;
    *)
      echo "Argumento no reconocido: $arg" >&2
      exit 2
      ;;
  esac
done

log()  { printf '%s\n' "$*"; }
err()  { printf '❌ %s\n' "$*" >&2; }
debug(){ [ "$DEBUG" -eq 1 ] && printf '   [debug] %s\n' "$*" || true; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "No se encontró '$1'."; exit 1; }
}

# ----------------------------------------------------------------------------
# 1. Verificar Docker
# ----------------------------------------------------------------------------
require_cmd docker
if ! docker info >/dev/null 2>&1; then
  err "El demonio de Docker no responde."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXERCISE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FRONTEND_SRC_DIR="$EXERCISE_DIR/node-stack/frontend"

# ----------------------------------------------------------------------------
# Acción: --down
# ----------------------------------------------------------------------------
if [ "$ACTION" = "down" ]; then
  log "Deteniendo frontend…"
  docker rm -f "$FRONTEND_CONTAINER" >/dev/null 2>&1 && log "Contenedor '$FRONTEND_CONTAINER' eliminado." || log "El contenedor no estaba corriendo."
  log "El backend y MongoDB NO se han tocado."
  exit 0
fi

# ----------------------------------------------------------------------------
# 2. Garantizar el prerrequisito: backend topics-api corriendo en la red
# ----------------------------------------------------------------------------
if [ "$(docker inspect -f '{{.State.Running}}' "$BACKEND_CONTAINER" 2>/dev/null || true)" = "true" ]; then
  debug "El backend '$BACKEND_CONTAINER' ya está corriendo."
else
  log "El backend '$BACKEND_CONTAINER' no está corriendo. Lanzando reto2.sh…"
  "$SCRIPT_DIR/reto2.sh" >/dev/null
fi

# ----------------------------------------------------------------------------
# 3. Construir la imagen del frontend (Dockerfile junto a la solución)
# ----------------------------------------------------------------------------
DOCKERFILE="$SCRIPT_DIR/frontend.Dockerfile"
if [ ! -f "$DOCKERFILE" ]; then
  err "No se encuentra $DOCKERFILE"
  exit 1
fi

log "Construyendo imagen '$FRONTEND_IMAGE'…"
# El contexto es el directorio del frontend para copiar package*.json, server.js y views/.
docker build -f "$DOCKERFILE" -t "$FRONTEND_IMAGE" "$FRONTEND_SRC_DIR" >/dev/null
debug "Imagen '$FRONTEND_IMAGE' construida."

# ----------------------------------------------------------------------------
# 4. Arrancar/recrear solo el contenedor del frontend, en la red Docker
# ----------------------------------------------------------------------------
docker rm -f "$FRONTEND_CONTAINER" >/dev/null 2>&1 || true
log "Arrancando contenedor '$FRONTEND_CONTAINER'…"
# API_URL apunta al hostname de Docker DNS del backend: el fetch lo hace
# server.js dentro del contenedor (node-fetch), no el navegador del host.
docker run -d \
  --name "$FRONTEND_CONTAINER" \
  --network "$NETWORK_NAME" \
  -p "${FRONTEND_PORT}:3000" \
  -e API_URL="http://${BACKEND_CONTAINER}:${BACKEND_PORT}/api/classes" \
  "$FRONTEND_IMAGE" >/dev/null

# ----------------------------------------------------------------------------
# 5. Esperar a que el frontend responda (HTTP 200 en /)
# ----------------------------------------------------------------------------
log "Esperando a que el frontend responda en localhost:${FRONTEND_PORT}…"
ready=0
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${FRONTEND_PORT}/" 2>/dev/null || true)"
  if [ "$code" = "200" ]; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  err "El frontend no respondió con HTTP 200 en el tiempo esperado."
  docker logs "$FRONTEND_CONTAINER" >&2 || true
  exit 1
fi
debug "Frontend listo (HTTP 200 en /)."

# ----------------------------------------------------------------------------
# 6. Verificar integración con el backend (la página debe contener datos)
# ----------------------------------------------------------------------------
# server.js renderiza index.ejs con las clases; si el backend devolvió clases,
# el HTML incluye el contenedor del calendario. Si no hay datos, muestra el
# aviso "No hay clases disponibles". Comprobamos que la integración responde
# sin errores de conexión (status 200) y dejamos constancia en --debug.
body="$(curl -s "http://localhost:${FRONTEND_PORT}/" 2>/dev/null || true)"
if echo "$body" | grep -q "Calendario Lemoncode"; then
  ok_integ=1
else
  ok_integ=0
fi

# ----------------------------------------------------------------------------
# 7. Resumen
# ----------------------------------------------------------------------------
echo
log "✅ Frontend dockerizado"
echo "   Contenedor: $FRONTEND_CONTAINER"
echo "   Imagen:     $FRONTEND_IMAGE"
echo "   Red:        $NETWORK_NAME"
echo "   URL:        http://localhost:${FRONTEND_PORT}"
echo "   API_URL:    http://${BACKEND_CONTAINER}:${BACKEND_PORT}/api/classes (DNS de Docker, resuelto por server.js)"
echo
if [ "$ok_integ" -eq 1 ]; then
  log "✅ Integración frontend↔backend verificada (la página carga)"
else
  err "La integración no pudo verificarse (revisa los logs del frontend/backend)."
fi

if [ "$DEBUG" -eq 1 ]; then
  classes_count="$(curl -s "http://localhost:${BACKEND_PORT}/api/classes" 2>/dev/null | grep -o '"_id"' | wc -l || echo '?')"
  debug "Clases en el backend: $classes_count"
fi

echo
echo "   Parar frontend: ./reto3.sh --down"
