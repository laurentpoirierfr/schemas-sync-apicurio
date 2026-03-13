#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Erreur: fichier d'environnement introuvable: $ENV_FILE"
  echo "Copier .env.exemple vers .env puis réessayer."
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

chmod +x "${ROOT_DIR}/scripts/generate-catalog.sh" "${ROOT_DIR}/scripts/sync-to-apicurio.sh" "${ROOT_DIR}/build.sh"

"${ROOT_DIR}/scripts/generate-catalog.sh" "${ROOT_DIR}/schemas" "${ROOT_DIR}/catalog"
"${ROOT_DIR}/build.sh"
