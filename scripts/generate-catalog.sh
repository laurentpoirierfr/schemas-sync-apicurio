#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-schemas}"
CATALOG_DIR="${2:-catalog}"
INDEX_FILE="${CATALOG_DIR}/index.csv"

if [[ ! -d "$ROOT_DIR" ]]; then
  echo "Erreur: répertoire introuvable: $ROOT_DIR"
  exit 1
fi

mkdir -p "$CATALOG_DIR"

trim_slash_suffix() {
  local value="$1"
  echo "${value%/}"
}

detect_artifact_type() {
  local category="$1"
  local file="$2"
  local filename
  filename="$(basename "$file")"

  case "$category" in
    asyncapi) echo "ASYNCAPI"; return 0 ;;
    graphql) echo "GRAPHQL"; return 0 ;;
    jsonschema) echo "JSON"; return 0 ;;
    openapi) echo "OPENAPI"; return 0 ;;
    avro) echo "AVRO"; return 0 ;;
    protobuf) echo "PROTOBUF"; return 0 ;;
    wsdl) echo "WSDL"; return 0 ;;
    xsd) echo "XSD"; return 0 ;;
    xml) echo "XML"; return 0 ;;
  esac

  case "$filename" in
    *.graphql|*.gql) echo "GRAPHQL" ;;
    *.avsc) echo "AVRO" ;;
    *.proto) echo "PROTOBUF" ;;
    *.wsdl) echo "WSDL" ;;
    *.xsd) echo "XSD" ;;
    *.xml) echo "XML" ;;
    *.yaml|*.yml|*.json) echo "JSON" ;;
    *) echo "JSON" ;;
  esac
}

to_artifact_id() {
  local file="$1"
  local name
  name="$(basename "$file")"
  echo "${name%.*}"
}

to_group_id() {
  local domain="$1"
  local category="$2"
  echo "${domain}-${category}"
}

ROOT_DIR="$(trim_slash_suffix "$ROOT_DIR")"
CATALOG_DIR="$(trim_slash_suffix "$CATALOG_DIR")"

tmp_index="$(mktemp)"
printf '# schema_path,group_id,artifact_id,artifact_type\n' > "$tmp_index"

declare -A domain_files

while IFS= read -r file; do
  rel="${file#${ROOT_DIR}/}"
  IFS='/' read -r domain category rest <<<"$rel"

  if [[ -z "$domain" || -z "$category" || -z "$rest" ]]; then
    echo "Skip (chemin non conforme): $file"
    continue
  fi

  group_id="$(to_group_id "$domain" "$category")"
  artifact_id="$(to_artifact_id "$file")"
  artifact_type="$(detect_artifact_type "$category" "$file")"

  line="${file},${group_id},${artifact_id},${artifact_type}"
  printf '%s\n' "$line" >> "$tmp_index"

  domain_file="${CATALOG_DIR}/${domain}.csv"
  if [[ -z "${domain_files[$domain_file]+x}" ]]; then
    domain_files[$domain_file]=1
    printf '# schema_path,group_id,artifact_id,artifact_type\n' > "$domain_file"
  fi
  printf '%s\n' "$line" >> "$domain_file"
done < <(find "$ROOT_DIR" -type f | sort)

mv "$tmp_index" "$INDEX_FILE"

echo "Catalog généré: $INDEX_FILE"
for domain_file in "${!domain_files[@]}"; do
  echo "Catalog généré: $domain_file"
done
