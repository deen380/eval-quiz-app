#!/usr/bin/env bash
# Déploie Quiz App sur Azure Container Apps.
# Prérequis : az login, docker lancé, être à la racine du dépôt.
# Variables obligatoires : ADMIN_PASSWORD
# Variables optionnelles : DATABASE_URL (Neon), JWT_SECRET, RESEND_API_KEY, FROM_EMAIL,
#                          ADMIN_USERNAME, RG, LOCATION, TAG
set -euo pipefail

: "${ADMIN_PASSWORD:?Définir ADMIN_PASSWORD (mot de passe admin fort)}"

RG="${RG:-rg-quiz}"
LOCATION="${LOCATION:-switzerlandnorth}"
ENV_NAME="${ENV_NAME:-env-quiz}"
SUB_ID="$(az account show --query id -o tsv)"
ACR_NAME="${ACR_NAME:-quizacr$(echo -n "$SUB_ID" | sha1sum | cut -c1-8)}"
TAG="${TAG:-$(git rev-parse --short HEAD)}"

ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 32)}"
RESEND_API_KEY="${RESEND_API_KEY:-re_placeholder}"
FROM_EMAIL="${FROM_EMAIL:-Quiz App <noreply@example.com>}"
DATABASE_URL="${DATABASE_URL:-postgres://placeholder:placeholder@localhost:5432/quiz}"

echo ">> Extension et fournisseurs Azure"
az config set extension.use_dynamic_install=yes_without_prompt -o none
az extension add --name containerapp --upgrade -o none
for ns in Microsoft.ContainerRegistry Microsoft.App Microsoft.OperationalInsights; do
  az provider register --namespace "$ns" --wait
done

echo ">> Groupe de ressources $RG ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" -o none

echo ">> Registre ACR $ACR_NAME"
az acr show -n "$ACR_NAME" -g "$RG" -o none 2>/dev/null || \
  az acr create -n "$ACR_NAME" -g "$RG" --sku Basic --admin-enabled true -o none
az acr login -n "$ACR_NAME"
SERVER="$(az acr show -n "$ACR_NAME" --query loginServer -o tsv)"
ACR_USER="$(az acr credential show -n "$ACR_NAME" --query username -o tsv)"
ACR_PASS="$(az acr credential show -n "$ACR_NAME" --query 'passwords[0].value' -o tsv)"

echo ">> Build et push des images (tag $TAG)"
docker build -t "$SERVER/quiz-frontend:$TAG" .
docker build -t "$SERVER/quiz-backend:$TAG" ./backend
docker push "$SERVER/quiz-frontend:$TAG"
docker push "$SERVER/quiz-backend:$TAG"

echo ">> Environnement Container Apps $ENV_NAME"
az containerapp env show -n "$ENV_NAME" -g "$RG" -o none 2>/dev/null || \
  az containerapp env create -n "$ENV_NAME" -g "$RG" -l "$LOCATION" -o none

echo ">> Backend (ingress interne, port 3007)"
if az containerapp show -n quiz-backend -g "$RG" -o none 2>/dev/null; then
  az containerapp registry set -n quiz-backend -g "$RG" --server "$SERVER" \
    --username "$ACR_USER" --password "$ACR_PASS" -o none
  az containerapp update -n quiz-backend -g "$RG" --image "$SERVER/quiz-backend:$TAG" -o none
else
  az containerapp create -n quiz-backend -g "$RG" --environment "$ENV_NAME" \
    --image "$SERVER/quiz-backend:$TAG" \
    --registry-server "$SERVER" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --ingress internal --target-port 3007 --transport http \
    --cpu 0.25 --memory 0.5Gi --min-replicas 1 --max-replicas 1 \
    --secrets "db-url=$DATABASE_URL" "jwt=$JWT_SECRET" "admin-pw=$ADMIN_PASSWORD" "resend=$RESEND_API_KEY" \
    --env-vars "DATABASE_URL=secretref:db-url" "JWT_SECRET=secretref:jwt" \
               "ADMIN_PASSWORD=secretref:admin-pw" "RESEND_API_KEY=secretref:resend" \
               "ADMIN_USERNAME=$ADMIN_USERNAME" "FROM_EMAIL=$FROM_EMAIL" "PORT=3007" \
    -o none
fi
BACK_FQDN="$(az containerapp show -n quiz-backend -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)"

echo ">> Frontend (ingress externe, port 80) -> backend $BACK_FQDN"
if az containerapp show -n quiz-frontend -g "$RG" -o none 2>/dev/null; then
  az containerapp registry set -n quiz-frontend -g "$RG" --server "$SERVER" \
    --username "$ACR_USER" --password "$ACR_PASS" -o none
  az containerapp update -n quiz-frontend -g "$RG" --image "$SERVER/quiz-frontend:$TAG" -o none
else
  az containerapp create -n quiz-frontend -g "$RG" --environment "$ENV_NAME" \
    --image "$SERVER/quiz-frontend:$TAG" \
    --registry-server "$SERVER" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --ingress external --target-port 80 --transport http \
    --cpu 0.25 --memory 0.5Gi --min-replicas 1 --max-replicas 2 \
    --env-vars "BACKEND_ADDR=$BACK_FQDN:443" "BACKEND_HOST=$BACK_FQDN" "BACKEND_SCHEME=https" \
    -o none
fi

FRONT_FQDN="$(az containerapp show -n quiz-frontend -g "$RG" --query properties.configuration.ingress.fqdn -o tsv)"
echo
echo "Images dans ACR :"
az acr repository list -n "$ACR_NAME" -o table
echo
echo "Application : https://$FRONT_FQDN"
echo "Health      : https://$FRONT_FQDN/health"
echo "Admin       : https://$FRONT_FQDN/gestion-quiz"
