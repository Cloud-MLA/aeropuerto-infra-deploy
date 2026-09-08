# scripts/

Automatización de la infra. El paso a paso narrado está en [`../RUNBOOK.md`](../RUNBOOK.md).

| Script | Dónde se corre | Qué hace |
|---|---|---|
| `user-data-common.sh` | user-data de las 4 EC2 | Instala Docker + compose plugin (Amazon Linux 2023) |
| `provision.sh` | tu máquina, con aws-cli del Learner Lab | Crea los 5 Security Groups, el bucket S3 y las 4 EC2. **La VPC se crea antes** con el asistente de la consola |
| `smoke-e2e.sh` | tu máquina | Prueba de humo E2E (BE-INT-08) contra la URL de API Gateway |
| `backup-db.sh` | VM-DB, antes de cerrar la sesión | `mysqldump` / `pg_dumpall` / `mongodump` → `s3://<bucket>/backups/` |
| `restore-db.sh` | VM-DB, tras un corte | Restaura desde el último backup en S3 |

## Orden típico

```bash
# 1. Consola: crear la VPC ("VPC and more") — RUNBOOK 1.1
# 2. Provisionar SG + S3 + EC2
export VPC_ID=vpc-xxx SUBNET_PRIV_A=subnet-aaa SUBNET_PRIV_B=subnet-bbb
./provision.sh
# 3. Consola: ALB + target group + VPC Link + API Gateway — RUNBOOK 1.8–1.9
# 4. Desplegar compose en VM-DB y VM-PROD (SSM) — RUNBOOK 1.6–1.7
# 5. Verificar
BASE="https://<api-id>.execute-api.us-east-1.amazonaws.com" ./smoke-e2e.sh
```

> Nota: en el Learner Lab no se pueden crear roles IAM. Las EC2 usan `LabInstanceProfile`
> (ya referenciado en `provision.sh`) y por eso acceden a S3 sin claves.
