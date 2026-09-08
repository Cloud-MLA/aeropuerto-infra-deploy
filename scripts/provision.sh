#!/bin/bash
# provision.sh — crea Security Groups, bucket S3 y las 4 EC2 con aws-cli.
# Mirror de la Parte 1 del RUNBOOK. La VPC/subredes/NAT se crean ANTES con el asistente
# "VPC and more" de la consola (es lo más rápido y fiable en el Learner Lab).
#
# Uso:
#   export VPC_ID=vpc-xxxx
#   export SUBNET_PRIV_A=subnet-xxxx SUBNET_PRIV_B=subnet-yyyy
#   ./provision.sh
#
# Requiere: aws-cli configurado con las credenciales del Learner Lab (región us-east-1).
set -euo pipefail

REGION=${AWS_REGION:-us-east-1}
BUCKET=${BUCKET:-mla-aeropuerto-lake}
AMI=${AMI:-$(aws ssm get-parameters --region "$REGION" \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)}
: "${VPC_ID:?define VPC_ID}"
: "${SUBNET_PRIV_A:?define SUBNET_PRIV_A}"
: "${SUBNET_PRIV_B:?define SUBNET_PRIV_B}"

echo ">> Región $REGION · VPC $VPC_ID · AMI $AMI"

sg() { # nombre descripcion  -> imprime el sg-id (lo crea si no existe)
  local name=$1 desc=$2 id
  id=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$name" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
  if [ "$id" = "None" ] || [ -z "$id" ]; then
    id=$(aws ec2 create-security-group --region "$REGION" --vpc-id "$VPC_ID" \
          --group-name "$name" --description "$desc" --query GroupId --output text)
  fi
  echo "$id"
}

echo ">> Security Groups"
SG_APIGW=$(sg sg-apigw-vpclink "VPC Link de API Gateway")
SG_ALB=$(sg   sg-alb           "ALB interno")
SG_PROD=$(sg  sg-vm-prod       "VMs de produccion")
SG_DB=$(sg    sg-vm-db         "VM de bases de datos")
SG_ING=$(sg   sg-vm-ingesta    "VM de ingesta")

authorize() { aws ec2 authorize-security-group-ingress --region "$REGION" "$@" 2>/dev/null || true; }
authorize --group-id "$SG_ALB"  --protocol tcp --port 80              --source-group "$SG_APIGW"
authorize --group-id "$SG_PROD" --protocol tcp --port 80              --source-group "$SG_ALB"
for p in 3306 5432 27017; do
  authorize --group-id "$SG_DB" --protocol tcp --port "$p" --source-group "$SG_PROD"
  authorize --group-id "$SG_DB" --protocol tcp --port "$p" --source-group "$SG_ING"
done
echo "   sg-alb=$SG_ALB sg-vm-prod=$SG_PROD sg-vm-db=$SG_DB sg-vm-ingesta=$SG_ING sg-apigw-vpclink=$SG_APIGW"

echo ">> Bucket S3 $BUCKET"
aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null || \
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
for k in raw/ athena-results/ backups/; do aws s3api put-object --bucket "$BUCKET" --key "$k" >/dev/null; done

echo ">> EC2 x4"
run_ec2() { # name type subnet sg
  local name=$1 type=$2 subnet=$3 sgid=$4
  local existing
  existing=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$name" "Name=instance-state-name,Values=pending,running,stopped,stopping" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  if [ -n "$existing" ]; then echo "   $name ya existe ($existing)"; return; fi
  aws ec2 run-instances --region "$REGION" --image-id "$AMI" --instance-type "$type" \
    --subnet-id "$subnet" --security-group-ids "$sgid" \
    --iam-instance-profile Name=LabInstanceProfile \
    --no-associate-public-ip-address \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=30,VolumeType=gp3}' \
    --user-data file://"$(dirname "$0")/user-data-common.sh" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name}]" \
    --query 'Instances[0].InstanceId' --output text
}
run_ec2 VM-PROD-1  t3.small  "$SUBNET_PRIV_A" "$SG_PROD"
run_ec2 VM-PROD-2  t3.small  "$SUBNET_PRIV_B" "$SG_PROD"
run_ec2 VM-DB      t3.medium "$SUBNET_PRIV_A" "$SG_DB"
run_ec2 VM-INGESTA t3.small  "$SUBNET_PRIV_B" "$SG_ING"

echo ">> Listo. Falta (consola): ALB interno, target group, VPC Link, API Gateway (ver RUNBOOK 1.8–1.9)."
