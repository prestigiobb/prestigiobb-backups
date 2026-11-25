# prestigiobb-backups

Fuente versionada del repo **público** `prestigiobb/prestigiobb-backups`, en la cuenta de GitHub del cliente. Este directorio es el contenido completo de ese repo y se publica tal cual. Qué hace y por qué está en [docs/plataforma/backups.md](../../docs/plataforma/backups.md).

- Es público para tener minutos ilimitados de GitHub Actions. Lo único público son los workflows, los scripts y la **clave pública** gpg. **Los datos nunca pasan por el repo**: se cifran en el runner y van a un bucket **privado** de Backblaze B2.
- Las credenciales viven en *GitHub Secrets*, que las enmascara. Los workflows sólo imprimen cantidades.

## Archivos
- `.github/workflows/daily-backup.yml`: todos los días a las 03:00 UTC (00:00 de Argentina) corre `scripts/respaldar.sh`, que arma un `pg_dump -Fc` del schema `public` y un tar con un CSV por tabla, los cifra con `backup-publica.asc` y deja sólo `prestigio-AAAA-MM-DD.dump.gpg` y `prestigio-AAAA-MM-DD.csv.tar.gpg`. `scripts/subir-b2.py` los sube a `B2_BUCKET_NAME/AAAA-MM-DD/`.
- `.github/workflows/keep-alive.yml`: a las 03:17 y 15:17 UTC hace `SELECT public.keepalive_beat()` con el rol `prestigio_keepalive` (escritura mínima en `keepalive_beats`, sin permisos sobre ninguna tabla de negocio; migración 0018). Si Supabase no responde, avisa que el proyecto puede estar pausado y el job falla (GitHub le manda el mail al dueño de la cuenta). Siempre deja un commit de latido por día en `latido.txt`: GitHub apaga los cron de un repo público después de 60 días sin commits.
- Tests en el repo de la app: `tests/architecture/backups-workflow.test.ts`, `tests/integration/platform/backup-respaldo.int.test.ts` (cifra, descifra y restaura con `pg_restore`), `latido-supabase.int.test.ts` y `keepalive.int.test.ts`.

## Secrets
| Secret | Valor |
|---|---|
| `SUPABASE_DB_URL` | Connection string de Supabase (URI, pooler en modo sesión) |
| `KEEPALIVE_DB_URL` | La misma URI pero con el usuario `prestigio_keepalive.<ref>` y su contraseña, `?sslmode=require` |
| `B2_KEY_ID` · `B2_APP_KEY` | Application Key restringida al bucket (Read and Write, sin listar otros buckets) |
| `B2_ENDPOINT` | `s3.<región>.backblazeb2.com` |
| `B2_BUCKET_NAME` | nombre del bucket privado |

## Estado (25/11/2026)
- ✅ Cuenta `prestigiobb`, repo de código en `prestigiobb/Prestigio-BB` y repo `prestigiobb/prestigiobb-backups` con este contenido.
- ✅ Par gpg generado: la pública es `backup-publica.asc`; la privada está en `~/secrets/prestigiobb/backup-privada.asc` del dev.
- ✅ Latido: rol `prestigio_keepalive` con login en prod (contraseña en `~/secrets/prestigiobb/keepalive-password.txt`), Secrets `KEEPALIVE_DB_URL` y `SUPABASE_DB_URL` cargados y `keep-alive.yml` habilitado.
- ✅ Backup viejo (`agustinpaul0/prestigiobb-backups`) apagado y repo borrado.
- ✅ B2: bucket `prestigiobb-backups` (privado, cifrado SSE-B2, retención de 180 días), key restringida al bucket y Secrets cargados; credenciales en `~/secrets/prestigiobb/b2-credentials.env`. Primer backup cifrado subido el 25/11 y restauración de prueba hecha.
- Pendiente: que GitHub ejecute los workflows. Los runs de `prestigiobb-backups` quedaron en cola sin jobs (cuenta nueva, a investigar).

## Pasos que faltan (en orden)
1. **Clave privada:** pasar `~/secrets/prestigiobb/backup-privada.asc` al gestor de contraseñas y a un segundo lugar (por ejemplo, un pendrive que guarde el cliente). Sin ella los backups no se pueden leer.
2. **Bucket B2:** crear un bucket **Private** (con *Default Encryption* SSE-B2) y una Application Key restringida a ese bucket.
3. **Retención de 6 meses:** en *Lifecycle Settings* del bucket, regla propia para todo el bucket (prefijo vacío): `daysFromUploadingToHiding: 180`, `daysFromHidingToDeleting: 1`. Todo backup con 6 meses o más se borra solo.
4. ✅ **Rol del latido en producción:** hecho el 25/11.
5. **Secrets de B2** (`SUPABASE_DB_URL` y `KEEPALIVE_DB_URL` ya están): cargarlos en el repo de backups (`gh secret set <NOMBRE> --repo prestigiobb/prestigiobb-backups`, leyendo el valor de la entrada estándar).
6. **Habilitar y probar:** `gh workflow enable` de los dos workflows, dispararlos a mano (`gh workflow run daily-backup.yml` y `keep-alive.yml`) y verificar la carpeta del día en el bucket y el commit de latido.
7. **Restauración de prueba** (abajo) en el contenedor local.
8. ✅ **Apagar lo viejo (hecho el 25/11, repo borrado):** deshabilitar los workflows de `agustinpaul0/prestigiobb-backups` y, con el nuevo andando, borrar ese repo (el token de `agustinpaul0` necesita el permiso `delete_repo`: `gh auth refresh -h github.com -u agustinpaul0 -s delete_repo`).
9. **Avisos de fallo:** GitHub manda el mail al correo de la cuenta del cliente; reenviarlo al del dev con un filtro.

## Restauración (probarla al menos una vez)
1. Descargar la carpeta del día desde B2.
2. Descifrar: `gpg --import backup-privada.asc` y `gpg --output prestigio.dump --decrypt prestigio-AAAA-MM-DD.dump.gpg`.
3. Crear una base vacía **sin** precrear `unaccent` (con ella, `--clean` no puede borrar el schema `public`) y restaurar: `pg_restore --no-owner --clean --if-exists -f - prestigio.dump | grep -v '^SET transaction_timeout' | psql -v ON_ERROR_STOP=1 "<url de la base vacía>"`. El `grep` hace falta sólo si la base destino es anterior a Postgres 17.
4. Crear la extensión que el dump no trae: `CREATE EXTENSION unaccent;` (sin ella falla la búsqueda de Auditoría). Comparar los conteos por tabla y entrar con un usuario admin. Probado el 25/11 con el backup bajado de B2: 131 productos, 76 clientes, 184 ventas y 1778 registros de auditoría iguales a prod.
5. Si el dump fallara, los CSV están en `prestigio-AAAA-MM-DD.csv.tar.gpg`: descifrar igual, `tar -xf` e importar con `\COPY tabla FROM 'tabla.csv' WITH CSV HEADER`, primero las tablas sin claves foráneas.
