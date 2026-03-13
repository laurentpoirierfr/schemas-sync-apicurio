#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-schemas}"

if [[ -z "${APICURIO_URL:-}" ]]; then
  echo "Erreur: APICURIO_URL est requis"
  exit 1
fi

APICURIO_URL="${APICURIO_URL%/}"
APICURIO_AUTH_TYPE="${APICURIO_AUTH_TYPE:-token}"
APICURIO_GROUP_PREFIX="${APICURIO_GROUP_PREFIX:-}"
CHANGED_FILES="${CHANGED_FILES:-}"
CATALOG_FILE="${CATALOG_FILE:-catalog/index.csv}"
CATALOG_DIR="${CATALOG_DIR:-catalog}"
DRY_RUN="${DRY_RUN:-false}"

is_truthy() {
  local value="${1:-}"
  case "${value,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

make_auth_headers() {
  case "$APICURIO_AUTH_TYPE" in
    none)
      return 0
      ;;
    token)
      if [[ -z "${APICURIO_TOKEN:-}" ]]; then
        echo "Erreur: APICURIO_TOKEN est requis quand APICURIO_AUTH_TYPE=token"
        exit 1
      fi
      echo "Authorization: Bearer ${APICURIO_TOKEN}"
      ;;
    basic)
      if [[ -z "${APICURIO_USERNAME:-}" || -z "${APICURIO_PASSWORD:-}" ]]; then
        echo "Erreur: APICURIO_USERNAME et APICURIO_PASSWORD sont requis quand APICURIO_AUTH_TYPE=basic"
        exit 1
      fi
      local encoded
      encoded="$(printf '%s:%s' "$APICURIO_USERNAME" "$APICURIO_PASSWORD" | base64 | tr -d '\n')"
      echo "Authorization: Basic ${encoded}"
      ;;
    *)
      echo "Erreur: APICURIO_AUTH_TYPE invalide (${APICURIO_AUTH_TYPE}). Valeurs supportées: none|token|basic"
      exit 1
      ;;
  esac
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

to_readable_label() {
  local value="$1"
  value="${value//[-_.]/ }"
  echo "$value"
}

default_artifact_name() {
  local domain="$1"
  local artifact_id="$2"
  echo "$(to_readable_label "$domain") $(to_readable_label "$artifact_id")"
}

default_artifact_description() {
  local domain="$1"
  local category="$2"
  local artifact_type="$3"
  local rel_path="$4"
  echo "Schema ${artifact_type} du domaine ${domain} categorie ${category} source ${rel_path}"
}

escape_json() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  echo "$value"
}

to_group_id() {
  local domain="$1"
  local category="$2"
  local base="${domain}-${category}"
  echo "${APICURIO_GROUP_PREFIX}${base}"
}

trim_spaces() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  echo "$value"
}

load_catalog_mapping_from_file() {
  local rel_path="$1"
  local catalog_path="$2"

  if [[ ! -f "$catalog_path" ]]; then
    return 1
  fi

  local line
  line="$(awk -F',' -v target="$rel_path" '
    /^[[:space:]]*#/ { next }
    NF < 4 { next }
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      if ($1 == target) {
        print $0
        exit
      }
    }
  ' "$catalog_path")"

  if [[ -z "$line" ]]; then
    return 1
  fi

  local mapped_artifact_name
  local mapped_artifact_description
  IFS=',' read -r schema_path mapped_group_id mapped_artifact_id mapped_artifact_type mapped_artifact_name mapped_artifact_description <<<"$line"

  schema_path="$(trim_spaces "$schema_path")"
  mapped_group_id="$(trim_spaces "$mapped_group_id")"
  mapped_artifact_id="$(trim_spaces "$mapped_artifact_id")"
  mapped_artifact_type="$(trim_spaces "$mapped_artifact_type")"
  mapped_artifact_name="$(trim_spaces "${mapped_artifact_name:-}")"
  mapped_artifact_description="$(trim_spaces "${mapped_artifact_description:-}")"

  if [[ -z "$mapped_group_id" || -z "$mapped_artifact_id" || -z "$mapped_artifact_type" ]]; then
    echo "Erreur: mapping incomplet dans ${catalog_path} pour ${rel_path}"
    exit 1
  fi

  CATALOG_GROUP_ID="$mapped_group_id"
  CATALOG_ARTIFACT_ID="$mapped_artifact_id"
  CATALOG_ARTIFACT_TYPE="$mapped_artifact_type"
  CATALOG_ARTIFACT_NAME="$mapped_artifact_name"
  CATALOG_ARTIFACT_DESCRIPTION="$mapped_artifact_description"
  return 0
}

load_catalog_mapping() {
  local rel_path="$1"
  local domain="$2"

  local domain_catalog="${CATALOG_DIR}/${domain}.csv"
  if load_catalog_mapping_from_file "$rel_path" "$domain_catalog"; then
    return 0
  fi

  if load_catalog_mapping_from_file "$rel_path" "$CATALOG_FILE"; then
    return 0
  fi

  return 1
}

publish_artifact() {
  local file="$1"

  local rel
  rel="${file#${ROOT_DIR}/}"

  IFS='/' read -r domain category rest <<<"$rel"
  if [[ -z "$domain" || -z "$category" || -z "$rest" ]]; then
    echo "Skip (chemin non conforme): $file"
    return 0
  fi

  local artifact_id
  artifact_id="$(basename "$file")"
  artifact_id="${artifact_id%.*}"

  local group_id
  group_id="$(to_group_id "$domain" "$category")"

  local artifact_type
  artifact_type="$(detect_artifact_type "$category" "$file")"

  local artifact_name
  artifact_name="$(default_artifact_name "$domain" "$artifact_id")"

  local artifact_description
  artifact_description="$(default_artifact_description "$domain" "$category" "$artifact_type" "$file")"

  if load_catalog_mapping "$file" "$domain"; then
    group_id="$CATALOG_GROUP_ID"
    artifact_id="$CATALOG_ARTIFACT_ID"
    artifact_type="$CATALOG_ARTIFACT_TYPE"
    if [[ -n "${CATALOG_ARTIFACT_NAME:-}" ]]; then
      artifact_name="$CATALOG_ARTIFACT_NAME"
    fi
    if [[ -n "${CATALOG_ARTIFACT_DESCRIPTION:-}" ]]; then
      artifact_description="$CATALOG_ARTIFACT_DESCRIPTION"
    fi
  fi

  local auth_header
  auth_header="$(make_auth_headers || true)"

  sync_artifact_metadata() {
    local target_group_id="$1"
    local target_artifact_id="$2"
    local target_artifact_name="$3"
    local target_artifact_description="$4"

    if is_truthy "$DRY_RUN"; then
      echo "[DRY_RUN] Meta: ${file} -> name=${target_artifact_name}, description=${target_artifact_description}"
      return 0
    fi

    local escaped_name
    escaped_name="$(escape_json "$target_artifact_name")"

    local escaped_description
    escaped_description="$(escape_json "$target_artifact_description")"

    local metadata_url
    metadata_url="${APICURIO_URL}/apis/registry/v2/groups/${target_group_id}/artifacts/${target_artifact_id}/meta"

    local payload
    payload="$(printf '{"name":"%s","description":"%s"}' "$escaped_name" "$escaped_description")"

    local metadata_args=(
      -sS
      -o /tmp/apicurio_meta_response.txt
      -w "%{http_code}"
      -X PUT
      -H "Content-Type: application/json"
    )

    if [[ -n "$auth_header" ]]; then
      metadata_args+=( -H "$auth_header" )
    fi

    metadata_args+=( --data "$payload" "$metadata_url" )

    local metadata_status
    metadata_status="$(curl "${metadata_args[@]}")"

    if [[ "$metadata_status" == "200" || "$metadata_status" == "201" || "$metadata_status" == "204" ]]; then
      echo "Métadonnées synchronisées: ${file} -> group=${target_group_id}, artifact=${target_artifact_id}"
      return 0
    fi

    echo "Erreur metadata (${metadata_status}) pour ${file}"
    cat /tmp/apicurio_meta_response.txt || true
    return 1
  }

  local get_url
  get_url="${APICURIO_URL}/apis/registry/v2/groups/${group_id}/artifacts/${artifact_id}"

  local tmp_remote
  tmp_remote="$(mktemp)"

  local get_args=(
    -sS
    -o "$tmp_remote"
    -w "%{http_code}"
    -X GET
    -H "Accept: */*"
  )

  if [[ -n "$auth_header" ]]; then
    get_args+=( -H "$auth_header" )
  fi

  get_args+=( "$get_url" )

  local current_status
  current_status="$(curl "${get_args[@]}")"

  local artifact_exists="false"
  if [[ "$current_status" == "200" ]]; then
    artifact_exists="true"
    if cmp -s "$file" "$tmp_remote"; then
      echo "Inchangé: ${file} -> group=${group_id}, artifact=${artifact_id} (skip)"
      rm -f "$tmp_remote"
      sync_artifact_metadata "$group_id" "$artifact_id" "$artifact_name" "$artifact_description"
      return $?
    fi
  elif [[ "$current_status" != "404" ]]; then
    echo "Erreur lecture artifact (${current_status}) pour ${file}"
    cat "$tmp_remote" || true
    rm -f "$tmp_remote"
    return 1
  fi

  rm -f "$tmp_remote"

  if is_truthy "$DRY_RUN"; then
    if [[ "$artifact_exists" == "true" ]]; then
      echo "[DRY_RUN] Update: ${file} -> group=${group_id}, artifact=${artifact_id}, type=${artifact_type}"
    else
      echo "[DRY_RUN] Create: ${file} -> group=${group_id}, artifact=${artifact_id}, type=${artifact_type}"
    fi
    sync_artifact_metadata "$group_id" "$artifact_id" "$artifact_name" "$artifact_description"
    return 0
  fi

  local create_url
  create_url="${APICURIO_URL}/apis/registry/v2/groups/${group_id}/artifacts?artifactId=${artifact_id}&artifactType=${artifact_type}"

  if [[ "$artifact_exists" == "true" ]]; then
    local update_url
    update_url="${APICURIO_URL}/apis/registry/v2/groups/${group_id}/artifacts/${artifact_id}"

    local update_args=(
      -sS
      -o /tmp/apicurio_response.txt
      -w "%{http_code}"
      -X PUT
      -H "Content-Type: application/octet-stream"
    )

    if [[ -n "$auth_header" ]]; then
      update_args+=( -H "$auth_header" )
    fi

    update_args+=( --data-binary "@${file}" "$update_url" )

    local update_status
    update_status="$(curl "${update_args[@]}")"

    if [[ "$update_status" == "200" || "$update_status" == "201" || "$update_status" == "204" ]]; then
      echo "Mis à jour: ${file} -> group=${group_id}, artifact=${artifact_id}, type=${artifact_type}"
      sync_artifact_metadata "$group_id" "$artifact_id" "$artifact_name" "$artifact_description"
      return $?
    fi

    echo "Erreur update (${update_status}) pour ${file}"
    cat /tmp/apicurio_response.txt || true
    return 1
  fi

  local create_args=(
    -sS
    -o /tmp/apicurio_response.txt
    -w "%{http_code}"
    -X POST
    -H "Content-Type: application/octet-stream"
  )

  if [[ -n "$auth_header" ]]; then
    create_args+=( -H "$auth_header" )
  fi

  create_args+=( --data-binary "@${file}" "$create_url" )

  local create_status
  create_status="$(curl "${create_args[@]}")"

  if [[ "$create_status" == "200" || "$create_status" == "201" ]]; then
    echo "Publié: ${file} -> group=${group_id}, artifact=${artifact_id}, type=${artifact_type}"
    sync_artifact_metadata "$group_id" "$artifact_id" "$artifact_name" "$artifact_description"
    return $?
  fi

  echo "Erreur create (${create_status}) pour ${file}"
  cat /tmp/apicurio_response.txt || true
  return 1
}

collect_files() {
  if [[ ! -d "$ROOT_DIR" ]]; then
    echo "Répertoire introuvable: $ROOT_DIR"
    return 1
  fi

  if [[ -n "$CHANGED_FILES" ]]; then
    local catalog_changed="false"
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if [[ "$path" == "$CATALOG_FILE" || "$path" == "$CATALOG_DIR"/* ]]; then
        catalog_changed="true"
      fi
      [[ "$path" != "$ROOT_DIR"/* ]] && continue
      [[ -f "$path" ]] || continue
      echo "$path"
    done <<< "$CHANGED_FILES"

    if [[ "$catalog_changed" == "true" ]]; then
      find "$ROOT_DIR" -type f | sort
    fi
    return 0
  fi

  find "$ROOT_DIR" -type f | sort
}

main() {
  local files
  files="$(collect_files)"

  if [[ -z "$files" ]]; then
    echo "Aucun fichier à synchroniser"
    return 0
  fi

  local count=0
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    publish_artifact "$file"
    count=$((count + 1))
  done <<< "$files"

  echo "Synchronisation terminée: ${count} fichier(s) traité(s)"
}

main "$@"
