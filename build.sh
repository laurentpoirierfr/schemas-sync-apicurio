#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "${SCRIPT_DIR}/scripts/sync-to-apicurio.sh"
"${SCRIPT_DIR}/scripts/sync-to-apicurio.sh" "${SCRIPT_DIR}/schemas"

