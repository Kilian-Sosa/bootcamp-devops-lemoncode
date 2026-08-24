#!/usr/bin/env bash
#
# crud-check.sh — Verificación CRUD representativa contra la API /api/classes.
#
# Crea una clase de prueba, la lee, la actualiza, la elimina y comprueba que
# ya no existe. Usa datos claramente identificables y los limpia al final.
#
# Uso:  ./crud-check.sh <base-url>
#   Ej:  ./crud-check.sh http://localhost:5000
#
# Diseñado para ser invocado por reto2.sh / reto4.sh, pero también usable a mano.
# ------------------------------------------------------------------------------

set -Eeuo pipefail

BASE_URL="${1:-http://localhost:5000}"
ENDPOINT="${BASE_URL}/api/classes"
created_id=""
deleted_id=""

# Marcador único para no colisionar con datos reales y poder limpiar luego.
MARK="crud-check-$(date +%s)-$$"
PAYLOAD="{\"name\":\"[TEST] ${MARK}\",\"instructor\":\"Test Bot\",\"startDate\":\"2025-01-01T10:00:00Z\",\"endDate\":\"2025-01-01T11:00:00Z\",\"duration\":1,\"level\":\"Beginner\"}"

ok()   { printf '   ✅ %s\n' "$*"; }
fail() { printf '   ❌ %s\n' "$*" >&2; }

cleanup() {
  if [ -n "$created_id" ]; then
    curl -s -o /dev/null -X DELETE "${ENDPOINT}/${created_id}" || true
  fi
}

trap cleanup EXIT

printf '🧪 Verificación CRUD contra %s\n' "$ENDPOINT"

# --- GET (lista inicial) ------------------------------------------------------
initial="$(curl -s -o /dev/null -w '%{http_code}' "$ENDPOINT" || true)"
[ "$initial" = "200" ] && ok "GET /api/classes → 200" || { fail "GET inicial → $initial"; exit 1; }

# --- POST (crear) -------------------------------------------------------------
post_response="$(curl -s -X POST "$ENDPOINT" -H 'Content-Type: application/json' -d "$PAYLOAD" -w $'\n%{http_code}' || true)"
post_status="${post_response##*$'\n'}"
post_body="${post_response%$'\n'*}"
if [ "$post_status" != "201" ]; then
  fail "POST → $post_status (esperado 201)"
  exit 1
fi
created_id="$(printf '%s' "$post_body" | sed -n 's/.*"_id":"\([^"]*\)".*/\1/p')"
if [ -z "$created_id" ]; then
  fail "POST no devolvió un _id"
  exit 1
fi
ok "POST → creado _id=$created_id"

# --- GET by id ----------------------------------------------------------------
code="$(curl -s -o /dev/null -w '%{http_code}' "${ENDPOINT}/${created_id}" || true)"
[ "$code" = "200" ] && ok "GET /${created_id} → 200" || { fail "GET by id → $code"; exit 1; }

# --- PUT (actualizar) ---------------------------------------------------------
PUT_PAYLOAD="{\"name\":\"[TEST-UPDATED] ${MARK}\",\"instructor\":\"Test Bot 2\",\"level\":\"Intermediate\"}"
code="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "${ENDPOINT}/${created_id}" -H 'Content-Type: application/json' -d "$PUT_PAYLOAD" || true)"
[ "$code" = "200" ] && ok "PUT /${created_id} → 200" || { fail "PUT → $code"; exit 1; }

# --- DELETE (eliminar) --------------------------------------------------------
code="$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "${ENDPOINT}/${created_id}" || true)"
[ "$code" = "204" ] && ok "DELETE /${created_id} → 204" || { fail "DELETE → $code"; exit 1; }
deleted_id="$created_id"
created_id=""

# --- GET by id (debe ser 404 tras borrar) -------------------------------------
code="$(curl -s -o /dev/null -w '%{http_code}' "${ENDPOINT}/${deleted_id}" || true)"
[ "$code" = "404" ] && ok "GET /${deleted_id} tras borrado → 404" || { fail "GET tras borrado → $code (esperado 404)"; exit 1; }

printf '✅ CRUD verificado correctamente\n'
