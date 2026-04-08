#!/bin/bash
set -euo pipefail

# Run on the EC2 instance to pull latest config, binary, and redeploy.
# Must be run from /opt/home-server.

BUCKET="lapinel-home-server-backup"
REGION="us-east-2"

echo "Fetching .env from SSM Parameter Store..."
aws ssm get-parameter \
  --region "$REGION" \
  --name "/home-server/.env" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > /etc/home-server/.env

echo "Ensuring data volume is mounted..."
mountpoint -q /opt/home-server-data || mount LABEL=home-server-data /opt/home-server-data

echo "Pulling latest repo changes..."
git pull --ff-only

echo "Downloading impostor binary from S3..."
aws s3 cp "s3://${BUCKET}/binaries/impostor" impostor/impostor
chmod +x impostor/impostor

echo "Redeploying stack..."
docker compose -f docker-compose.yml -f docker-compose.remote.yml --env-file /etc/home-server/.env up -d --build

echo "Initializing restic repository if needed..."
set -a; source /etc/home-server/.env; set +a
restic snapshots >/dev/null 2>&1 || restic init

echo "Ensuring daily backup cron job is configured..."
command -v crond >/dev/null 2>&1 || dnf install -y cronie
systemctl enable --now crond
echo "0 2 * * * root /opt/home-server/backup.sh >> /var/log/home-server-backup.log 2>&1" > /etc/cron.d/home-server-backup

echo "Deploy complete."
