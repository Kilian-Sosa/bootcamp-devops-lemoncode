#!/usr/bin/env bash
#
# reto4.sh — Reto 4: Orquestación con Docker Compose.
#
# Levanta la pila completa (MongoDB + backend + frontend) usando compose.yml,
# verifica que los servicios están sanos, valida la API y el frontend, y ejecuta
# una verificación CRUD representativa. El uso directo de `docker compose` sigue
# siendo posible (ver README.md).
#
# Uso:
#   ./reto4.sh            Levanta la pila completa con --build y valida.
#   ./reto4.sh --debug    Igual, pero con trazas detalladas.
#   ./reto4.sh --down     Detiene la pila (conserva el volumen de MongoDB).
#   ./reto4.sh --down -v  Detiene la pila y elimina el volumen de MongoDB.
#
# Comandos equivalentes a mano:
#   docker compose up --build -d
#   docker compose ps
#   docker compose logs -f
#   docker compose down        # conserva el volumen
#   docker compose down -v     # elimina el volumen
# ------------------------------------------------------------------------------

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Configuración (nombres estables y propios de este ejercicio)
# ----------------------------------------------------------------------------
COMPOSE_FILE_NAME="compose.yml"
FRONTEND_PORT="3000"
BACKEND_PORT="5000"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
DEBUG=0
ACTION="up"
REMOVE_VOLUMES=""

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=1 ;;
    --down)  ACTION="down" ;;
    -v)      REMOVE_VOLUMES="-v" ;;
    -h|--help)
      sed -n '3,25p' "$0"
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
# 1. Verificar Docker + Compose
# ----------------------------------------------------------------------------
require_cmd docker
if ! docker info >/dev/null 2>&1; then
  err "El demonio de Docker no responde."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  err "El plugin `docker compose` no está disponible."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ----------------------------------------------------------------------------
# Acción: --down
# ----------------------------------------------------------------------------
if [ "$ACTION" = "down" ]; then
  log "Deteniendo la pila…"
  if [ -n "$REMOVE_VOLUMES" ]; then
    docker compose -f "$COMPOSE_FILE_NAME" down -v
    log "Pila detenida y volumen 'lemoncode-mongo-data' eliminado."
  else
    docker compose -f "$COMPOSE_FILE_NAME" down
    log "Pila detenida. El volumen 'lemoncode-mongo-data' se ha conservado."
  fi
  exit 0
fi

# ----------------------------------------------------------------------------
# 2. Validar la configuración de Compose antes de levantar
# ----------------------------------------------------------------------------
log "Validando compose.yml…"
docker compose -f "$COMPOSE_FILE_NAME" config >/dev/null
debug "compose config OK."

# ----------------------------------------------------------------------------
# 3. Levantar la pila completa con build
# ----------------------------------------------------------------------------
log "Construyendo y levantando la pila completa (puede tardar la primera vez)…"
docker compose -f "$COMPOSE_FILE_NAME" up --build -d
debug "docker compose up ejecutado."

# ----------------------------------------------------------------------------
# 4. Esperar a que los servicios estén sanos (healthchecks definidos en compose)
# ----------------------------------------------------------------------------
log "Esperando a que los servicios estén sanos…"
all_healthy=0
for _ in $(seq 1 60); do
  # Comprobar con inspect de los contenedores conocidos (fiable y sin parsear ps).
  mongo_health="$(docker inspect -f '{{.State.Health.Status}}' lemoncode-mongo 2>/dev/null || echo 'none')"
  back_health="$(docker inspect -f '{{.State.Health.Status}}' topics-api 2>/dev/null || echo 'none')"
  front_running="$(docker inspect -f '{{.State.Running}}' topics-front 2>/dev/null || echo 'false')"
  if [ "$mongo_health" = "healthy" ] && [ "$back_health" = "healthy" ] && [ "$front_running" = "true" ]; then
    all_healthy=1
    break
  fi
  sleep 2
done

if [ "$all_healthy" -ne 1 ]; then
  err "No todos los servicios alcanzaron estado healthy."
  docker compose -f "$COMPOSE_FILE_NAME" ps
  docker compose -f "$COMPOSE_FILE_NAME" logs --tail=40
  exit 1
fi
debug "Todos los servicios sanos."

# ----------------------------------------------------------------------------
# 5. Verificar endpoints reales (no solo contenedor arrancado)
# ----------------------------------------------------------------------------
log "Verificando backend en localhost:${BACKEND_PORT}…"
ready=0
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${BACKEND_PORT}/api/classes" 2>/dev/null || true)"
  [ "$code" = "200" ] && { ready=1; break; }
  sleep 1
done
[ "$ready" -ne 1 ] && { err "El backend no responde con 200."; exit 1; }
debug "Backend responde (HTTP 200)."

log "Verificando frontend en localhost:${FRONTEND_PORT}…"
ready=0
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${FRONTEND_PORT}/" 2>/dev/null || true)"
  [ "$code" = "200" ] && { ready=1; break; }
  sleep 1
done
[ "$ready" -ne 1 ] && { err "El frontend no responde con 200."; exit 1; }
debug "Frontend responde (HTTP 200)."

# Verificar que la página realmente carga contenido del backend.
front_body="$(curl -s "http://localhost:${FRONTEND_PORT}/" 2>/dev/null || true)"
if echo "$front_body" | grep -q "Calendario Lemoncode"; then
  log "✅ Integración frontend↔backend verificada (la página renderiza)"
else
  err "El frontend no renderiza el contenido esperado."
fi

# ----------------------------------------------------------------------------
# 6. Verificación CRUD representativa
# ----------------------------------------------------------------------------
log "Ejecutando verificación CRUD contra el backend…"
"$SCRIPT_DIR/crud-check.sh" "http://localhost:${BACKEND_PORT}"

# ----------------------------------------------------------------------------
# 7. Resumen
# ----------------------------------------------------------------------------
echo
log "✅ Pila completa levantada y validada"
echo
docker compose -f "$COMPOSE_FILE_NAME" ps
echo
echo "   Frontend: http://localhost:${FRONTEND_PORT}"
echo "   Backend:  http://localhost:${BACKEND_PORT}/api/classes"
echo "   MongoDB:  localhost:27017 (volumen: lemoncode-mongo-data)"
echo
echo "   Logs:           docker compose logs -f"
echo "   Parar:          ./reto4.sh --down        (conserva el volumen)"
echo "   Parar y borrar: ./reto4.sh --down -v     (elimina el volumen)"
