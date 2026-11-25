#!/usr/bin/env bash
set -euo pipefail
umask 077

USO="uso: respaldar.sh <carpeta-destino> <clave-publica.asc>"
DESTINO="${1:?$USO}"
CLAVE="${2:?$USO}"
: "${DATABASE_URL:?falta DATABASE_URL}"
PG_BIN="${PG_BIN:-}"
FECHA="${BACKUP_DATE:-$(date -u +%F)}"

TRABAJO=$(mktemp -d)
trap 'rm -rf "$TRABAJO"' EXIT
export GNUPGHOME="$TRABAJO/gnupg"
mkdir -m 700 "$GNUPGHOME" "$TRABAJO/csv"
gpg --batch --quiet --import "$CLAVE" 2>/dev/null
DESTINATARIO=$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr/ {print $10; exit}')
[ -n "$DESTINATARIO" ] || { echo "La clave pública no es válida" >&2; exit 1; }

"${PG_BIN}pg_dump" "$DATABASE_URL" --format=custom --schema=public --no-owner --no-privileges \
  --file="$TRABAJO/prestigio.dump"

TABLAS=$("${PG_BIN}psql" "$DATABASE_URL" -v ON_ERROR_STOP=1 -At -c \
  "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename;")
CANTIDAD=0
for TABLA in $TABLAS; do
  "${PG_BIN}psql" "$DATABASE_URL" -v ON_ERROR_STOP=1 -q \
    -c "\\COPY public.\"$TABLA\" TO '$TRABAJO/csv/$TABLA.csv' WITH CSV HEADER"
  CANTIDAD=$((CANTIDAD + 1))
done
[ "$CANTIDAD" -gt 0 ] || { echo "No se exportó ninguna tabla" >&2; exit 1; }
tar -C "$TRABAJO" -cf "$TRABAJO/csv.tar" csv

cifrar() {
  gpg --batch --quiet --trust-model always --recipient "$DESTINATARIO" --output "$2" --encrypt "$1"
}
mkdir -p "$DESTINO"
cifrar "$TRABAJO/prestigio.dump" "$DESTINO/prestigio-$FECHA.dump.gpg"
cifrar "$TRABAJO/csv.tar" "$DESTINO/prestigio-$FECHA.csv.tar.gpg"
echo "Backup cifrado: $CANTIDAD tablas en 2 archivos"
