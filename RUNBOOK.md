# RUNBOOK — Infraestructura AWS (Learner Lab)

Aeropuerto Internacional Jorge Chávez · Proyecto Parcial CS2032.
Entorno: **AWS Academy Learner Lab** (sesión ~4 h, solo `LabRole`, sin IAM propio).

- **Parte 1 — Provisión inicial** (una vez): crear toda la infra desde la consola.
- **Parte 2 — Reinicio tras corte de sesión** (objetivo < 15 min): volver a dejar todo operativo.
- **Parte 3 — Apagado / limpieza**: qué parar y qué borrar para no gastar crédito.

Referencias: [`docs/arquitectura.md`](https://github.com/btoroled/cloud-computing-proyecto/blob/main/docs/arquitectura.md) ·
[`docs/aws-learner-lab-hallazgos.md`](https://github.com/btoroled/cloud-computing-proyecto/blob/main/docs/aws-learner-lab-hallazgos.md).

---

## 0. Antes de tocar nada

- **Región:** `us-east-1` (N. Virginia) — la única garantizada en el Learner Lab. Cámbiala arriba a la derecha.
- Anota el **crédito restante** (banner del lab).
- Donde pida *IAM role* → **`LabRole`**. Donde pida *instance profile* → **`LabInstanceProfile`**.
  No crear roles/usuarios/políticas IAM (bloqueado).
- **Sin key pairs.** Acceso a instancias por **SSM Session Manager**.
- El temporizador (~4 h) **apaga** (no borra) las instancias EC2. EBS, VPC, SG, ALB y S3 persisten.
  Las **IP públicas cambian** al reiniciar → usar siempre DNS del ALB / URL de API Gateway, nunca IPs.

Valores de referencia usados en este runbook:

| Recurso | Valor |
|---|---|
| VPC | `aeropuerto` — `10.0.0.0/16` |
| Subredes | `public1` (1a) `10.0.0.0/24` · `public2` (1b) `10.0.1.0/24` · `private1` (1a) `10.0.10.0/24` · `private2` (1b) `10.0.11.0/24` |
| Bucket S3 | `mla-aeropuerto-lake` (prefijos `raw/`, `athena-results/`, `backups/`) — el nombre es **global**, si ya existe (probable) agrega un prefijo propio, ej. `btl-mla-aeropuerto-lake`, y ajusta todos los comandos de este documento que lo referencian |
| Glue DB | `aeropuerto_lake` |
| AMI EC2 | `ami-01112e374e42e3f3c` — Cloud9 Ubuntu 22 (la usada en clases) · verificar arquitectura (x86_64/arm64) al lanzar |

---

## Parte 1 — Provisión inicial

### 1.1 Red — VPC  · BE-INT-01 · ~5 min

**VPC → Create VPC → "VPC and more"**:

| Campo | Valor |
|---|---|
| Name tag | `aeropuerto` |
| IPv4 CIDR | `10.0.0.0/16` |
| Number of AZs | 2 |
| Public subnets | 2 |
| Private subnets | 2 |
| NAT gateways | **In 1 AZ** |
| VPC endpoints | **S3 Gateway** |
| DNS hostnames / resolution | enabled |

Deja: VPC, 2 subredes públicas + 2 privadas, IGW, 1 NAT en `public1`, route tables
(pública → IGW, privadas → NAT), endpoint S3.

### 1.2 Security Groups  · BE-INT-01 · ~10 min

**VPC → Security Groups**. Crear las 5 vacías en la VPC `aeropuerto`, luego editar reglas
(outbound: dejar la default "all traffic"):

| SG | Inbound |
|---|---|
| `sg-apigw-vpclink` | *(ninguno)* |
| `sg-alb` | TCP **80** desde `sg-apigw-vpclink` |
| `sg-vm-prod` | TCP **80** desde `sg-alb` |
| `sg-vm-db` | TCP **3306, 5432, 27017** desde `sg-vm-prod` **y** desde `sg-vm-ingesta` |
| `sg-vm-ingesta` | *(ninguno)* |

### 1.3 S3 — data lake  · DS-04 · ~3 min

**S3 → Create bucket**: `mla-aeropuerto-lake`, `us-east-1`, **Block all public access ON**.
Crear prefijos: `raw/`, `athena-results/`, `backups/`.

### 1.4 EC2 — 4 instancias  · BE-INT-02 · ~15 min

**EC2 → Launch instance** (lanzar 1, luego "Launch more like this").

Config común:
- AMI: **`ami-01112e374e42e3f3c`** (Cloud9 Ubuntu 22, la de clases — buscarla por ID en "Browse more AMIs", pestañas "Owned by me"/"Private images") · Key pair: **Proceed without a key pair**
- Network: VPC `aeropuerto` · Subred **privada** correspondiente (ver tabla) · **Auto-assign public IP: Disable**
- Firewall: **Select existing security group** (nunca "Create security group" — el wizard abre SSH 0.0.0.0/0 por default)
- Advanced → **IAM instance profile: `LabInstanceProfile`** — imprescindible: sin esto el agente SSM no tiene permiso y la instancia no aparece conectable en 1.5
- Storage: 30 GB gp3
- Advanced → **User data** (Ubuntu usa `apt`, no `dnf`; usuario default `ubuntu`, no `ec2-user`):

```bash
#!/bin/bash
apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker
usermod -aG docker ubuntu
id -u ssm-user &>/dev/null || useradd -m ssm-user
usermod -aG docker ssm-user
echo "ssm-user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ssm-agent-users
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

> Esta AMI de Cloud9 probablemente ya trae Docker instalado — el script no rompe nada si ya está, solo confirma que quede encendido. Si el agente SSM no viene preconfigurado (poco probable, Cloud9 lo usa para el propio IDE), la instancia no va a conectar en el paso 1.5 — en ese caso, relanzar esa instancia puntual con Amazon Linux 2023 como respaldo.

> **⚠️ Esta AMI de Cloud9 trae servicios nativos preinstalados y corriendo que ocupan los mismos puertos que vamos a publicar por Docker**: `mysql.service` en el **3306** (choca con `VM-DB`) y `apache2.service` en el **80** (choca con `nginx` en `VM-PROD`). Sale como `Error ... failed to bind host port ...: address already in use` al hacer `docker compose up`. Antes de levantar cualquier compose, revisa y libera el puerto:
> ```bash
> sudo ss -ltnp | grep ':80\|:3306'
> sudo systemctl stop apache2.service mysql.service   # el que aplique
> sudo systemctl disable apache2.service mysql.service
> ```
> Si el contenedor ya se creó una vez con el puerto ocupado, aunque liberes el puerto después puede quedar sin el mapeo publicado (`docker ps` no muestra el puerto) — fuerza que se recree: `sudo docker compose up -d --force-recreate <servicio>`.

> **⚠️ La sesión de SSM Session Manager arranca en `sh` (dash), no en `bash`.** Cosas como `read -s -p "..." VAR` (para no mostrar contraseñas/tokens en pantalla) fallan con `Illegal option -s`. Corre `bash` como primer comando de la sesión si vas a usar ese patrón.

| Name | Type | Subnet | Security group |
|---|---|---|---|
| `VM-PROD-1` | t3.small | private1 (1a) | `sg-vm-prod` |
| `VM-PROD-2` | t3.small | private2 (1b) | `sg-vm-prod` |
| `VM-DB` | t3.medium | private1 (1a) | `sg-vm-db` |
| `VM-INGESTA` | t3.small | private2 (1b) | `sg-vm-ingesta` |

### 1.5 Verificar SSM  · DoD de BE-INT-02

EC2 → cada instancia → **Connect → Session Manager → Connect**. Debe abrir shell en las 4.
- Si sale gris: esperar 2–3 min (el agente se registra por el NAT); confirmar instance profile `LabInstanceProfile`.
- Dentro: `docker --version && docker compose version`.

### 1.6 VM-DB — motores de base de datos  · BE-INT-03 · F1

SSM a `VM-DB`:

```bash
sudo mkdir -p /opt/db && cd /opt/db
sudo tee docker-compose.yml >/dev/null <<'YML'
services:
  mysql:
    image: mysql:8
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: pasajeros
    ports: ["3306:3306"]
    volumes: ["mysql-data:/var/lib/mysql"]
  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: vuelos
    ports: ["5432:5432"]
    volumes: ["pg-data:/var/lib/postgresql/data"]
  mongo:
    image: mongo:7
    ports: ["27017:27017"]
    volumes: ["mongo-data:/data/db"]
volumes: { mysql-data: {}, pg-data: {}, mongo-data: {} }
YML
sudo tee .env >/dev/null <<'ENV'
MYSQL_ROOT_PASSWORD=cambia-esto
POSTGRES_PASSWORD=cambia-esto
ENV
sudo docker compose up -d
sudo docker compose ps
```

> **⚠️ No uses `$`, `\`, comillas ni backticks en las contraseñas.** Docker Compose interpreta `$` como interpolación de variables en `.env` (un `$` suelto al final de línea se descarta silenciosamente al leer el archivo), y el entrypoint de la imagen `mysql:8` mete la contraseña en una sentencia SQL donde `\` se trata como escape — la combinación produce una contraseña *distinta* a la que escribiste, y falla con `Access denied for user 'root'@'localhost' (using password: YES)` justo al crear la base. Usa solo letras, números y como mucho `-`/`_`. Verifica que quedó bien ANTES de levantar los contenedores:
> ```bash
> sudo docker compose config   # debe mostrar la misma contraseña que pusiste en .env, sin recortes
> ```
> Si ya levantaste con una contraseña rota, el volumen queda con una inicialización a medias — hace falta `sudo docker compose down -v` (se pierden los datos) antes de reintentar con la contraseña corregida.

Anotar la **IP privada** de `VM-DB` — es la que van en los `.env` de los microservicios. Para verla desde dentro de la instancia: `hostname -I`, o en consola: EC2 → instancia → columna **Private IPv4 addresses**.

### 1.7 VM-PROD ×2 — nginx + MS1..MS5  · BE-INT-04 · F1

SSM a `VM-PROD-1` y `VM-PROD-2` (mismo procedimiento en las dos — **son instancias
completamente independientes, nada se comparte entre ellas**: hay que repetir mkdir,
archivos, `.env`, login a GHCR y `up` en cada una). El `docker-compose.yml` de producción
y el `nginx.conf` ya están en este repo: `compose/vm-prod/docker-compose.yml` y `nginx/nginx.conf`.

> **⚠️ No pegues archivos largos (heredocs de 50+ líneas) directo en la terminal del navegador de Session Manager** — se puede corromper el pegado (líneas duplicadas/cortadas) sin ningún error visible. Mejor: sube los 2 archivos a S3 una vez desde tu máquina y bájalos con `aws s3 cp` dentro de la instancia (usa las credenciales del `LabInstanceProfile` automáticamente, sin configurar nada):
> ```bash
> # subir una vez, desde tu máquina, a S3 → deploy/vm-prod/docker-compose.yml y nginx.conf
> # en la instancia:
> sudo mkdir -p /opt/prod && cd /opt/prod
> sudo aws s3 cp s3://<bucket>/deploy/vm-prod/docker-compose.yml .
> sudo aws s3 cp s3://<bucket>/deploy/vm-prod/nginx.conf .
> sha256sum docker-compose.yml nginx.conf   # compara contra el hash de los archivos originales
> ```
> El `.env` (corto, ~10 líneas) sí se puede pegar directo con `sudo tee .env >/dev/null <<'ENV' ... ENV` sin problema.

`.env` (ajusta `DB_HOST` a la IP privada real de `VM-DB`, y usa las mismas contraseñas del paso 1.6):
```bash
sudo tee .env >/dev/null <<'ENV'
DB_HOST=<ip-privada-VM-DB>
MYSQL_ROOT_PASSWORD=<misma-que-VM-DB>
POSTGRES_PASSWORD=<misma-que-VM-DB>
ATHENA_OUTPUT=s3://<bucket>/athena-results/
TAG_MS1=latest
TAG_MS2=latest
TAG_MS3=latest
TAG_MS4=latest
TAG_MS5=latest
TAG_SWAGGER=latest
ENV
```

Login a GHCR (los paquetes quedan **privados** por defecto al publicarlos desde CI):
```bash
bash   # la sesión SSM arranca en sh, read -s necesita bash
read -s -p "GHCR token: " GHCR_TOKEN && echo
echo "$GHCR_TOKEN" | sudo docker login ghcr.io -u <tu-usuario-github> --password-stdin
```

> **⚠️ Usa un Personal Access Token CLÁSICO (`ghp_...`), no fine-grained (`github_pat_...`), aunque seas owner de la org.** Un fine-grained PAT solo tiene acceso a los paquetes de la organización si eliges explícitamente esa org como "Resource owner" al crearlo — si quedó como tu cuenta personal, el login funciona (solo valida identidad) pero el `pull` falla con `not found` aunque la imagen exista (GHCR responde 404 en vez de 403 por privacidad). Un PAT clásico con scope `read:packages` no tiene ese problema. Alternativa de fondo: hacer los paquetes **públicos** en GitHub → org → Packages → Package settings → Change visibility (si el mensaje dice *"Setting is disabled by organization administrators"*, hay que habilitarlo primero en Org Settings → Packages).

```bash
sudo docker compose pull nginx ms1 ms2 ms3 ms4 ms5
sudo docker compose up -d nginx ms1 ms2 ms3 ms4 ms5
sudo docker compose ps -a
curl -s -w "\nHTTP_STATUS:%{http_code}\n" localhost/api/pasajeros/health
```

Si `swagger-aggregator` todavía no tiene imagen publicada (bloqueado por Frontend), coméntalo en `nginx.conf` (el `upstream swagger` y las rutas `/docs`) — si no, nginx falla al arrancar con `host not found in upstream "swagger-aggregator:8080"` porque no puede resolver un contenedor que no existe. Cuando la imagen exista: descomentar, `sudo docker compose up -d nginx swagger-aggregator`.

**Convención de healthcheck por microservicio** (para probar, no asumas que todos usan `/health`):
`ms1`/`ms3`/`ms4`/`ms5` → `/api/<ruta>/health` · **`ms2` (Java/Spring) → `/api/vuelos/actuator/health`**.

### 1.8 ALB interno  · BE-INT-05 · F1

**EC2 → Load balancers → Create → Application Load Balancer**:
- Scheme: **Internal** · VPC `aeropuerto` · subredes `private1` + `private2`
- Security group: `sg-alb`
- Target group `tg-vm-prod`: target type **Instances**, protocolo HTTP **80**,
  health check path `/api/pasajeros/health` → registrar `VM-PROD-1` y `VM-PROD-2`
- Listener HTTP **80** → forward a `tg-vm-prod`

Anotar el **DNS del ALB**.

### 1.9 API Gateway + VPC Link  · BE-INT-06 · F1

1. **API Gateway → VPC links → Create (for HTTP APIs)**: VPC `aeropuerto`, subredes privadas,
   SG `sg-apigw-vpclink`. Esperar `AVAILABLE` (~2 min).
2. **API Gateway → Create API → HTTP API**:
   - Integration: **Private resource** → ALB → listener 80 → VPC link creado
   - Route: `ANY /{proxy+}`
   - Stage: `$default`, auto-deploy
3. Copiar la **Invoke URL** (`https://<api-id>.execute-api.us-east-1.amazonaws.com`).
   Probar: `curl -s <invoke-url>/api/pasajeros/health`.
4. Pasar esa URL a Alexander (`VITE_API_BASE`) y a la matriz de verificación.

> **⚠️ El asistente a veces crea la ruta `ANY /{proxy+}` sin asociarle la integración.** Verifica en la ruta creada (Routes → click en la ruta) que la sección "Integración" **no** diga "No hay ninguna integración asociada" — si dice eso, asóciala manualmente a la integración privada (VPC Link → ALB) antes de probar.

### 1.10 Glue + Athena  · Data Science · F2

- **Glue → Databases → Add database** `aeropuerto_lake`.
- **Glue → Crawlers**: 1 por prefijo (`raw/ms1/`, `raw/ms2/`, `raw/ms3/`), IAM role `LabRole`,
  destino DB `aeropuerto_lake`. Ejecutar cuando la ingesta haya subido datos.
- **Athena → Settings**: query result location `s3://mla-aeropuerto-lake/athena-results/`.

### 1.11 VM-INGESTA  · DS-05 · F1/F2

SSM a `VM-INGESTA`: `docker compose` con los 3 contenedores de `aeropuerto-data-science/ingesta/`.
Necesita alcanzar la IP privada de `VM-DB` (SG ya lo permite) y S3 (por el endpoint / NAT).
`LabRole` de la instancia da permiso a S3 — no hay que configurar credenciales.

---

## Parte 2 — Reinicio tras corte de sesión  (objetivo < 15 min)

Tras un corte, la VPC / SG / ALB / S3 **siguen existiendo**; solo hay que re-encender EC2 y
levantar contenedores. Las IP privadas **se conservan** (mismas ENIs) salvo que se hayan
terminado instancias.

1. **Iniciar el Learner Lab** y esperar credenciales.
2. **EC2 → Instances**: seleccionar las 4 → **Instance state → Start**. Esperar `2/2 checks`.
3. **SSM a `VM-DB`** → `cd /opt/db && sudo docker compose up -d && sudo docker compose ps`.
   Si los volúmenes se perdieron, restaurar dumps desde `s3://mla-aeropuerto-lake/backups/` (paso 3.3).
4. **SSM a `VM-PROD-1` y `VM-PROD-2`** → `cd /opt/prod && sudo docker compose up -d`.
5. **EC2 → Target groups → `tg-vm-prod`**: verificar que los 2 targets quedan `healthy`
   (si no, re-registrarlos — a veces se des-registran al parar la instancia).
6. **Probar la URL de API Gateway**: `curl -s <invoke-url>/api/pasajeros/health` → `{"status":"UP"...}`.
7. Si el **NAT Gateway** fue borrado: recrearlo (VPC → NAT gateways → Create, subred `public1`,
   Elastic IP nueva) y apuntar `0.0.0.0/0` al nuevo NAT. **Ojo:** el wizard "VPC and more" crea
   **una route table privada por AZ** (`...-rtb-private1-us-east-1a` y `...-rtb-private2-us-east-1b`),
   no una sola compartida — hay que actualizar la ruta en **las dos**, aunque solo haya 1 NAT.
   Síntoma de que falta esto: SSM Agent en el log de la instancia tira
   `dial tcp ...:443: i/o timeout` al intentar reportarse (sin salida a internet).
8. Si la **URL de API Gateway cambió** (API recreada): avisar a Alexander para rebuild del frontend.

### 2.x Backups de BD (correr ANTES de cerrar sesión)

SSM a `VM-DB`:

```bash
TS=$(date +%Y%m%d-%H%M)
sudo docker exec db-mysql-1     sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases' > /tmp/mysql-$TS.sql
sudo docker exec db-postgres-1  sh -c 'pg_dumpall -U postgres'                                    > /tmp/pg-$TS.sql
sudo docker exec db-mongo-1     sh -c 'mongodump --archive'                                       > /tmp/mongo-$TS.archive
aws s3 cp /tmp/mysql-$TS.sql    s3://mla-aeropuerto-lake/backups/
aws s3 cp /tmp/pg-$TS.sql       s3://mla-aeropuerto-lake/backups/
aws s3 cp /tmp/mongo-$TS.archive s3://mla-aeropuerto-lake/backups/
```

(Ajustar los nombres de contenedor a los que muestre `docker compose ps`.)

---

## Parte 3 — Apagado / limpieza

| Al terminar por hoy | Al terminar el proyecto |
|---|---|
| `Stop` las 4 EC2 (se apagan solas igual) | Terminar las 4 EC2 |
| Correr los backups (Parte 2.x) | Borrar ALB, target group, VPC Link, API Gateway |
| Si no vuelves en 1–2 días: **borrar el NAT Gateway** (sigue cobrando apagado) + su Elastic IP | Borrar NAT + Elastic IP, endpoints, VPC |
| — | Vaciar y borrar el bucket S3 (o dejar solo evidencias) |
| — | Borrar crawlers y DB de Glue |

Costo dominante en reposo: **NAT Gateway** (~US$1–1.5/día) y **Elastic IP sin usar**.

---

## Evidencias para el informe

Capturar (van a `docs/evidencias/`):
- VPC resource map · tabla de SG · bucket S3 con prefijos
- EC2 list (4 instancias, sin IP pública) · una sesión SSM abierta
- Target group con 2 targets `healthy` · VPC Link `AVAILABLE`
- `curl` a la URL de API Gateway respondiendo · `nc -zv <alb-dns> 80` **fallando** desde fuera
