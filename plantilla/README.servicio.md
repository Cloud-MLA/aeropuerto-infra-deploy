# <msX>-<nombre>-api

<Una línea: qué microservicio es y a qué dominio corresponde.>

Parte del Proyecto Parcial CS2032 — Cloud Computing (Ciclo 2026-2).
Contexto y arquitectura: [`cloud-computing-proyecto`](https://github.com/btoroled/cloud-computing-proyecto).

- **Stack:** <Python + FastAPI + MySQL 8 | Java + Spring Boot + PostgreSQL 16 | Node + Express + MongoDB 7>
- **Puerto interno:** `<8001..8005>`
- **Contrato:** [`openapi.yaml`](openapi.yaml)
- **Depende de:** <MS2 para validar vuelos | ninguno | Athena>

## Levantar en local

```bash
cp .env.example .env      # ajustar credenciales
docker compose up --build
curl -s localhost:<PORT>/health
```

- Swagger-UI: `http://localhost:<PORT>/docs`
- OpenAPI JSON: `http://localhost:<PORT>/openapi.json`

## Migraciones / seed (si aplica)

```bash
# MS1: alembic upgrade head   ·   MS2: Flyway corre al arrancar   ·   MS3: ajv valida, sin migración
# Seed de desarrollo:
<comando>
```

## Levantar tras un corte de sesión del lab

La imagen se descarga de GHCR; el servicio no guarda estado. En la VM-PROD:

```bash
cd /opt/prod && docker compose pull <servicio> && docker compose up -d <servicio>
```

## Pruebas

```bash
<pytest -q | mvn -q test | npm test>
```

Mínimo: 1 caso feliz + 1 validación de error (ver [contrato de errores](https://github.com/btoroled/cloud-computing-proyecto/blob/main/docs/contratos/errores.md)).

## Publicar imagen

Push de un tag `vX.Y` → GitHub Actions construye y publica `ghcr.io/cloud-mla/<repo>:vX.Y`.

```bash
git tag v1.0 && git push origin v1.0
```

## Endpoints

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Estado del servicio (+ dependencias si aplica) |
| GET | `/docs` | Swagger-UI |
| ... | ... | ... |
