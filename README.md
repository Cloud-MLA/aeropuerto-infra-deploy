# aeropuerto-infra-deploy

Infraestructura y despliegue del Proyecto Parcial CS2032 — Cloud Computing (Ciclo 2026-2).
Dominio: **Aeropuerto Internacional Jorge Chávez**. Entorno: **AWS Academy Learner Lab**.

## Contenido

| Archivo / carpeta | Qué es | Estado |
|---|---|---|
| [`RUNBOOK.md`](RUNBOOK.md) | Provisión inicial paso a paso (consola), reinicio tras corte de sesión (< 15 min) y limpieza | ✅ v1 |
| `compose/vm-db/` | `docker-compose.yml` de la VM de bases de datos (mysql 8 + postgres 16 + mongo 7) | ⬜ pendiente |
| `compose/vm-prod/` | `docker-compose.yml` de producción (nginx + MS1..MS5 + swagger) | ⬜ pendiente |
| `nginx/nginx.conf` | Reverse proxy por path (`/api/pasajeros`, `/api/vuelos`, …) | ⬜ pendiente |
| `scripts/` | `aws-cli` / `user-data` para recrear la infra | ⬜ pendiente |

## Arquitectura

Ver [`docs/arquitectura.md`](https://github.com/btoroled/cloud-computing-proyecto/blob/main/docs/arquitectura.md)
en el repo de documentación. Resumen:

```
Internet → API Gateway (HTTPS) → VPC Link → ALB interno → nginx → MS1..MS5
                                                                    ↓
                                                          VM-DB (privada)
VM-INGESTA → S3 (raw/msX/) → Glue → Athena → MS5
```

## Uso rápido

- **Primera vez:** seguir [`RUNBOOK.md`](RUNBOOK.md) Parte 1.
- **Tras un corte de sesión del lab:** [`RUNBOOK.md`](RUNBOOK.md) Parte 2.
- **Antes de cerrar el lab:** correr los backups de BD (RUNBOOK 2.x) y `Stop` de las EC2.

Dueño: Benja (Líder / Arquitecto).
