# Plantilla de repo de microservicio (BE-TX-02)

Punto de partida común para `ms1-pasajeros-api`, `ms2-vuelos-api`, `ms3-infraestructura-api`,
`ms4-manifiesto-api` y `ms5-analitica-api`. Copiar lo que aplique según el stack.

## Qué copiar a tu repo

| Archivo de aquí | Va en tu repo como | Aplica a |
|---|---|---|
| `.editorconfig` | `.editorconfig` | todos |
| `.gitignore` | fusionar con el tuyo | todos |
| `.env.example` | `.env.example` (ajusta las claves) | todos |
| `README.servicio.md` | `README.md` | todos |
| `docker/Dockerfile.python` | `Dockerfile` | MS1, MS4, MS5 |
| `docker/Dockerfile.java` | `Dockerfile` | MS2 |
| `docker/Dockerfile.node` | `Dockerfile` | MS3 |
| `github/workflows/build-push-ghcr.yml` | `.github/workflows/build-push-ghcr.yml` | todos |

## Convenciones (obligatorias)

- **`GET /health`** siempre disponible (MS2 usa `GET /actuator/health`). Devuelve `{"status":"UP", ...}`.
- **`GET /docs`** con Swagger-UI; el `openapi.json` servible en `/openapi.json`.
- Puerto interno por servicio (lo espera el `nginx.conf` de producción):
  MS1 `8001` · MS2 `8002` · MS3 `8003` · MS4 `8004` · MS5 `8005`. Configurable por env `PORT`.
- Errores con el [contrato común](https://github.com/btoroled/cloud-computing-proyecto/blob/main/docs/contratos/errores.md).
- Enums y rangos de ID: [diccionario compartido](https://github.com/btoroled/cloud-computing-proyecto/blob/main/docs/contratos/enums.md).
- Imagen publicada en **GHCR**: `ghcr.io/cloud-mla/<repo>:<tag>` al hacer push de un tag `vX.Y`.
- Contenedor corre como **usuario no-root**.

## Estructura sugerida

```
<repo>/
  src/ (o app/)          código
  tests/                 pruebas mínimas (happy path + 1 validación de error)
  migrations/            migraciones de BD (MS1/MS2) — Alembic / Flyway
  openapi.yaml           contrato (contract-first, se versiona)
  Dockerfile
  docker-compose.yml     app + su BD, para desarrollo local
  .env.example
  .editorconfig
  .github/workflows/build-push-ghcr.yml
  README.md
```
