#!/usr/bin/env bash
set -uo pipefail

: "${DATABASE_URL:?falta DATABASE_URL}"
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-15}"

if psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -qtAc 'SELECT public.keepalive_beat()' > /dev/null 2>&1; then
  echo "Supabase respondió: latido registrado."
  exit 0
fi

echo "::error::Supabase no responde: el proyecto puede estar pausado (el plan Free lo pausa a los 7 días sin actividad) o la credencial del latido es inválida. Reanudarlo en el Dashboard de Supabase → Resume project."
exit 1
