#!/usr/bin/env bash
# Supprime TOUTES les ressources du groupe (ACR, environnement, apps).
set -euo pipefail
RG="${RG:-rg-quiz}"
read -r -p "Supprimer le groupe de ressources $RG et tout son contenu ? (oui/non) " rep
[ "$rep" = "oui" ] || { echo "Annulé."; exit 0; }
az group delete -n "$RG" --yes --no-wait
echo "Suppression lancée (quelques minutes)."
