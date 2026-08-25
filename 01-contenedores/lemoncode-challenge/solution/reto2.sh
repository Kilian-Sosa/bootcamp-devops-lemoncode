#!/usr/bin/env bash
#
# reto2.sh — Reto 2: Dockerizar el backend Node.js.
#
# Garantiza la infraestructura de MongoDB (Reto 1), construye la imagen del
# backend, arranca el contenedor `topics-api` en `lemoncode-network` y verifica
# que la API responde y se conecta a MongoDB.
#
# Uso:
#   ./reto2.sh            Construye y arranca el backend.
#   ./reto2.sh --debug    Igual, pero con trazas detalladas.
#   ./reto2.sh --down     Detiene y elimina el contenedor del backend (no toca
#                         MongoDB ni su volumen).
#   ./reto2.sh --test     Tras arrancar, ejecuta una verificación CRUD completa.
#
# El backend se conecta a MongoDB por DNS de Docker (mongodb://lemoncode-mongo:27017)
# y se publica en localhost:5000.
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Configuración (nombres estables y propios de este ejercicio)
# ----------------------------------------------------------------------------
NETWORK_NAME="lemoncode-network"
MONGO_CONTAINER="lemoncode-mongo"
MONGO_VOLUME="lemoncode-mongo-data"
MONGO_IMAGE="mongo:7.0"
MONGO_PORT="27017"
MONGO_DB_NAME="ClassesDb"

BACKEND_IMAGE="lemoncode-backend"
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
    --test)  ACTION="test" ;;
    -h|--help)
      sed -n '3,22p' "$0"
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

# Reutiliza la infraestructura del Reto 1 sin destruirla.
ensure_mongo() {
  if [ "$ACTION" = "down" ]; then
    return 0
  fi
  debug "Asegurando infraestructura de MongoDB (delega en reto1.sh)…"
  if ! docker inspect "$MONGO_CONTAINER" >/dev/null 2>&1; then
    log "MongoDB no está creado. Lanzando reto1.sh…"
    "$SCRIPT_DIR/reto1.sh" >/dev/null
  elif [ "$(docker inspect -f '{{.State.Running}}' "$MONGO_CONTAINER" 2>/dev/null)" != "true" ]; then
    log "MongoDB está parado. Lanzando reto1.sh…"
    "$SCRIPT_DIR/reto1.sh" >/dev/null
  else
    debug "MongoDB ya está corriendo."
  fi
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
BACKEND_SRC_DIR="$EXERCISE_DIR/node-stack/backend"

# ----------------------------------------------------------------------------
# Acción: --down
# ----------------------------------------------------------------------------
if [ "$ACTION" = "down" ]; then
  log "Deteniendo backend…"
  docker rm -f "$BACKEND_CONTAINER" >/dev/null 2>&1 && log "Contenedor '$BACKEND_CONTAINER' eliminado." || log "El contenedor no estaba corriendo."
  log "MongoDB y su volumen NO se han tocado."
  exit 0
fi

# ----------------------------------------------------------------------------
# 2. Garantizar MongoDB + red (prerrequisito del Reto 1)
# ----------------------------------------------------------------------------
ensure_mongo

# ----------------------------------------------------------------------------
# 3. Construir la imagen del backend (Dockerfile junto a la solución)
# ----------------------------------------------------------------------------
DOCKERFILE="$SCRIPT_DIR/backend.Dockerfile"
if [ ! -f "$DOCKERFILE" ]; then
  err "No se encuentra $DOCKERFILE"
  exit 1
fi

log "Construyendo imagen '$BACKEND_IMAGE'…"
# El contexto es el directorio del backend para copiar package*.json y app.js.
docker build -f "$DOCKERFILE" -t "$BACKEND_IMAGE" "$BACKEND_SRC_DIR" >/dev/null
debug "Imagen '$BACKEND_IMAGE' construida."

# ----------------------------------------------------------------------------
# 4. Arrancar/recrear solo el contenedor del backend
# ----------------------------------------------------------------------------
# Conexión a MongoDB por DNS de Docker (lemoncode-mongo resuelve dentro de la red).
docker rm -f "$BACKEND_CONTAINER" >/dev/null 2>&1 || true
log "Arrancando contenedor '$BACKEND_CONTAINER'…"
docker run -d \
  --name "$BACKEND_CONTAINER" \
  --network "$NETWORK_NAME" \
  -p "${BACKEND_PORT}:5000" \
  -e DATABASE_URL="mongodb://${MONGO_CONTAINER}:${MONGO_PORT}" \
  -e DATABASE_NAME="$MONGO_DB_NAME" \
  -e HOST="0.0.0.0" \
  -e PORT="5000" \
  "$BACKEND_IMAGE" >/dev/null

# ----------------------------------------------------------------------------
# 5. Esperar a que la API esté realmente lista (GET /api/classes responde)
# ----------------------------------------------------------------------------
log "Esperando a que la API responda en localhost:${BACKEND_PORT}…"
ready=0
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${BACKEND_PORT}/api/classes" 2>/dev/null || true)"
  if [ "$code" = "200" ]; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  err "La API no respondió con HTTP 200 en el tiempo esperado."
  docker logs "$BACKEND_CONTAINER" >&2 || true
  exit 1
fi
debug "API lista (HTTP 200 en /api/classes)."

# ----------------------------------------------------------------------------
# 6. Resumen
# ----------------------------------------------------------------------------
echo
log "✅ Backend dockerizado y conectado a MongoDB"
echo "   Contenedor: $BACKEND_CONTAINER"
echo "   Imagen:     $BACKEND_IMAGE"
echo "   Red:        $NETWORK_NAME"
echo "   API:        http://localhost:${BACKEND_PORT}/api/classes"
echo "   MongoDB:    mongodb://${MONGO_CONTAINER}:${MONGO_PORT} (DNS de Docker)"
echo

if [ "$ACTION" = "test" ]; then
  "$SCRIPT_DIR/crud-check.sh" "http://localhost:${BACKEND_PORT}"
fi

echo "   Parar backend: ./reto2.sh --down"
