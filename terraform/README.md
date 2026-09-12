# Terraform — infraestructura de red y cómputo

Reproduce por código lo que `../RUNBOOK.md` Parte 1 hace a mano en consola: VPC, 5 Security
Groups, bucket S3, 4 EC2, ALB interno y API Gateway + VPC Link. **No** gestiona lo que corre
dentro de las instancias (compose de VM-DB/VM-PROD, contenedores de ingesta) — eso sigue por
SSM, como en el RUNBOOK 1.6/1.7/1.9/1.11.

## Por qué esto y no solo la consola

El Learner Lab **no se queda sin crédito de un día para otro** entre sesiones normales de clase —
el riesgo real es que **la sesión (~4h) corta las credenciales** y, si terminas las instancias o
pierdes la VPC, tienes que rehacer todo el clic-a-clic del RUNBOOK. Con esto, reconstruir es
`terraform apply` en ~5 minutos en vez de ~45.

Esto **no** te salva si el crédito de la cuenta llega a $0 — ahí no hay herramienta que valga,
necesitas cuenta con saldo. Es para reconstruir rápido, no para evadir el límite de crédito.

## Requisitos

- Terraform ≥ 1.5.
- Credenciales temporales del Learner Lab: **AWS Details → AWS CLI → Show** (te da
  `aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`). Duran lo mismo que la sesión.

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_DEFAULT_REGION=us-east-1
```

Repetir esto (nuevas credenciales) cada vez que reinicies el Lab — el token viejo deja de servir.

## Uso

```bash
cd terraform
terraform init
terraform plan     # revisar qué va a crear antes de aplicar
terraform apply
```

Al terminar, guarda las salidas (`alb_dns_name`, `api_invoke_url`, IPs privadas) — son las que
necesitas pasar a los `.env` de los microservicios y a Alexander (`VITE_API_BASE`).

```bash
terraform output
```

## Qué NO crea (y por qué)

- **Roles/usuarios IAM** — bloqueado en el Lab. Todo usa `LabRole` / `LabInstanceProfile` ya
  existentes, referenciados por `data` sources, nunca creados.
- **Key pairs EC2** — acceso solo por SSM Session Manager, igual que en consola.
- **`docker compose` de las apps** (VM-DB, VM-PROD, VM-INGESTA) — eso son pasos manuales por SSM
  (RUNBOOK 1.6/1.7/1.9/1.11) porque dependen de imágenes que aún no existen en el momento de
  provisionar la red.

## Antes de cerrar el Lab por hoy

`terraform destroy` **no es obligatorio** — el temporizador solo *apaga* las EC2 (Parte 2 del
RUNBOOK las vuelve a prender). Solo corre `destroy` cuando termines el proyecto del todo, o si el
NAT Gateway te está comiendo crédito en reposo (~US$1–1.5/día) y no vas a volver en 1–2 días.

## Troubleshooting rápido

| Error | Causa típica |
|---|---|
| `UnauthorizedOperation` en `aws_iam_instance_profile` | El nombre no es exactamente `LabInstanceProfile` en esta cuenta — verificar en IAM → Roles |
| `terraform apply` cuelga en el NAT Gateway | Normal, tarda 1–3 min en aprovisionar |
| Bucket S3 con `BucketAlreadyExists` | El nombre es global — cambiar `bucket_name` en `terraform.tfvars` |
| VPC Link se queda `PENDING` mucho tiempo | Normal, tarda ~2 min en pasar a `AVAILABLE` (igual que en consola) |
