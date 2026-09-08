#!/bin/bash
# backup-db.sh — dump de las 3 BD a S3. Correr en la VM-DB ANTES de cerrar la sesión del lab.
#   ./backup-db.sh              # usa el bucket por defecto
#   BUCKET=mi-bucket ./backup-db.sh
set -euo pipefail

BUCKET=${BUCKET:-mla-aeropuerto-lake}
TS=$(date +%Y%m%d-%H%M)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# nombres de contenedor según compose/vm-db/docker-compose.yml
docker exec db-mysql sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases' > "$TMP/mysql-$TS.sql"
docker exec db-postgres sh -c 'exec pg_dumpall -U postgres'                                   > "$TMP/pg-$TS.sql"
docker exec db-mongo sh -c 'exec mongodump --archive'                                         > "$TMP/mongo-$TS.archive"

for f in "$TMP"/*; do
  aws s3 cp "$f" "s3://$BUCKET/backups/$(basename "$f")"
done
echo "OK -> s3://$BUCKET/backups/  (mysql-$TS.sql, pg-$TS.sql, mongo-$TS.archive)"
