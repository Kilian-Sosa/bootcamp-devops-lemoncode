#!/usr/bin/env bash
#
# reto1.sh — Reto 1: MongoDB en contenedor + backend en local.
#
# Crea la red Docker `lemoncode-network`, arranca MongoDB en un contenedor con
# volumen con nombre (persistencia) y expone el puerto 27017 para que el backend
# Node.js ejecutado localmente pueda conectarse a `mongodb://localhost:27017`.
#
# Uso:
#   ./reto1.sh            Arranca/verifica la infraestructura de MongoDB.
#   ./reto1.sh --debug    Igual, pero con trazas de diagnóstico detalladas.
#   ./reto1.sh --down     Detiene y elimina el contenedor de MongoDB (sin tocar
#                         el volumen, los datos se conservan).
#
# El backend Node.js se ejecuta EN LOCAL (ver README.md para los comandos).
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Configuración (nombres estables y propios de este ejercicio)
# ----------------------------------------------------------------------------
NETWORK_NAME="lemoncode-network"
MONGO_IMAGE="mongo:7.0"
MONGO_CONTAINER="lemoncode-mongo"
MONGO_VOLUME="lemoncode-mongo-data"
MONGO_PORT="27017"
MONGO_DB_NAME="ClassesDb"        # coincide con el valor por defecto de app.js

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
      sed -n '3,20p' "$0"
      exit 0
      ;;
    *)
      echo "Argumento no reconocido: $arg" >&2
      exit 2
      ;;
  esac
done

# Ruta absoluta a la raíz del ejercicio (para localizar el backend local).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXERCISE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$EXERCISE_DIR/node-stack/backend"

log()  { printf '%s\n' "$*"; }
err()  { printf '❌ %s\n' "$*" >&2; }
debug(){ [ "$DEBUG" -eq 1 ] && printf '   [debug] %s\n' "$*" || true; }

# Comprueba que un binario está disponible.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "No se encontró '$1'. Instálalo y vuelve a intentarlo."; exit 1; }
}

# ----------------------------------------------------------------------------
# 1. Verificar que Docker está disponible
# ----------------------------------------------------------------------------
require_cmd docker
if ! docker info >/dev/null 2>&1; then
  err "El demonio de Docker no responde. Arranca Docker Desktop / el servicio docker."
  exit 1
fi
debug "Docker disponible: $(docker --version)"

# ----------------------------------------------------------------------------
# 2. Crear la red `lemoncode-network` si no existe (idempotente)
# ----------------------------------------------------------------------------
if [ "$ACTION" = "down" ]; then
  log "Deteniendo MongoDB…"
  docker rm -f "$MONGO_CONTAINER" >/dev/null 2>&1 && log "Contenedor '$MONGO_CONTAINER' eliminado." || log "El contenedor no estaba corriendo."
  log "El volumen '$MONGO_VOLUME' NO se ha tocado: los datos de MongoDB se conservan."
  exit 0
fi

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  debug "La red '$NETWORK_NAME' ya existe."
else
  log "Creando red Docker '$NETWORK_NAME'…"
  docker network create \
    --label com.docker.compose.project=solution \
    --label "com.docker.compose.network=$NETWORK_NAME" \
    "$NETWORK_NAME" >/dev/null
fi

# ----------------------------------------------------------------------------
# 3. Volumen con nombre para persistencia (idempotente)
# ----------------------------------------------------------------------------
if docker volume inspect "$MONGO_VOLUME" >/dev/null 2>&1; then
  debug "El volumen '$MONGO_VOLUME' ya existe (datos conservados)."
else
  log "Creando volumen '$MONGO_VOLUME'…"
  docker volume create "$MONGO_VOLUME" >/dev/null
fi

# ----------------------------------------------------------------------------
# 4. Arrancar MongoDB con nombre predecible y puerto 27017 (idempotente)
# ----------------------------------------------------------------------------
# Si ya existe el contenedor y está parado, se arranca; si está corriendo, nada.
if docker inspect "$MONGO_CONTAINER" >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' "$MONGO_CONTAINER" 2>/dev/null)" = "true" ]; then
    debug "El contenedor '$MONGO_CONTAINER' ya está corriendo."
  else
    log "Arrancando contenedor '$MONGO_CONTAINER' existente…"
    docker start "$MONGO_CONTAINER" >/dev/null
  fi
else
  log "Arrancando MongoDB ($MONGO_IMAGE) en el contenedor '$MONGO_CONTAINER'…"
  docker run -d \
    --name "$MONGO_CONTAINER" \
    --network "$NETWORK_NAME" \
    -p "${MONGO_PORT}:27017" \
    -v "${MONGO_VOLUME}:/data/db" \
    "$MONGO_IMAGE" >/dev/null
fi

# ----------------------------------------------------------------------------
# 5. Esperar a que MongoDB esté realmente listo (ping con mongosh)
# ----------------------------------------------------------------------------
log "Esperando a que MongoDB acepte conexiones…"
ready=0
for _ in $(seq 1 30); do
  if docker exec "$MONGO_CONTAINER" mongosh --quiet --eval 'db.adminCommand({ ping: 1 })' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  err "MongoDB no respondió al ping en el tiempo esperado."
  docker logs "$MONGO_CONTAINER" >&2 || true
  exit 1
fi
debug "MongoDB responde al ping."

# ----------------------------------------------------------------------------
# 6. Resumen
# ----------------------------------------------------------------------------
echo
log "✅ MongoDB listo en Docker"
echo "   Red:        $NETWORK_NAME"
echo "   Contenedor: $MONGO_CONTAINER"
echo "   Imagen:     $MONGO_IMAGE"
echo "   Volumen:    $MONGO_VOLUME (persistencia de datos)"
echo "   Puerto:     localhost:${MONGO_PORT}"
echo "   Base datos: $MONGO_DB_NAME  (colección: Classes)"
echo
echo "👉 Para arrancar el backend EN LOCAL (desde node-stack/backend):"
echo "   npm install"
echo "   DATABASE_URL=mongodb://localhost:${MONGO_PORT} \\"
echo "   DATABASE_NAME=${MONGO_DB_NAME} \\"
echo "   npm start"
echo
echo "   URL API:     http://localhost:5000/api/classes"
echo "   REST Client: node-stack/backend/client.http"
echo
echo "   Parar MongoDB:   ./reto1.sh --down"
