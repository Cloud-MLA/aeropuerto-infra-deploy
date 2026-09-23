#!/bin/sh
# Se ejecuta DENTRO de VM-DB (bajado de S3 por backup-db.sh). Todo el timestamp y las
# variables se resuelven aca, nunca en la maquina local que dispara el SSM Run Command.
set -e

BUCKET="${1:-mla-aeropuerto-lake}"
TS="$(date +%Y%m%d-%H%M)"

MYSQL_CT="$(docker ps --filter name=db-mysql --format '{{.Names}}' | head -1)"
PG_CT="$(docker ps --filter name=db-postgres --format '{{.Names}}' | head -1)"
MONGO_CT="$(docker ps --filter name=db-mongo --format '{{.Names}}' | head -1)"

docker exec "$MYSQL_CT" sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases' > "/tmp/mysql-$TS.sql"
docker exec "$PG_CT" sh -c 'pg_dumpall -U postgres' > "/tmp/pg-$TS.sql"
docker exec "$MONGO_CT" sh -c 'mongodump --archive' > "/tmp/mongo-$TS.archive"

aws s3 cp "/tmp/mysql-$TS.sql" "s3://$BUCKET/backups/"
aws s3 cp "/tmp/pg-$TS.sql" "s3://$BUCKET/backups/"
aws s3 cp "/tmp/mongo-$TS.archive" "s3://$BUCKET/backups/"
rm -f "/tmp/mysql-$TS.sql" "/tmp/pg-$TS.sql" "/tmp/mongo-$TS.archive"

echo "OK: 3 dumps subidos con timestamp $TS"
