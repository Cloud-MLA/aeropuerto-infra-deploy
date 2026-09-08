#!/bin/bash
# restore-db.sh — restaura las 3 BD desde el último backup en S3. Correr en la VM-DB
# tras un corte de sesión si los volúmenes se perdieron. Ver RUNBOOK Parte 2.
#   ./restore-db.sh            # toma el backup más reciente de cada motor
set -euo pipefail

BUCKET=${BUCKET:-mla-aeropuerto-lake}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

latest() { aws s3 ls "s3://$BUCKET/backups/" | awk -v p="$1" '$4 ~ p {print $4}' | sort | tail -1; }

MYSQL_F=$(latest '^mysql-');  PG_F=$(latest '^pg-');  MONGO_F=$(latest '^mongo-')
echo "mysql=$MYSQL_F  pg=$PG_F  mongo=$MONGO_F"

aws s3 cp "s3://$BUCKET/backups/$MYSQL_F" "$TMP/$MYSQL_F"
aws s3 cp "s3://$BUCKET/backups/$PG_F"    "$TMP/$PG_F"
aws s3 cp "s3://$BUCKET/backups/$MONGO_F" "$TMP/$MONGO_F"

docker exec -i db-mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' < "$TMP/$MYSQL_F"
docker exec -i db-postgres sh -c 'exec psql -U postgres' < "$TMP/$PG_F"
docker exec -i db-mongo sh -c 'exec mongorestore --archive --drop' < "$TMP/$MONGO_F"
echo "OK — restaurado."
