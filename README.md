# Schema Sync Apicurio (GitHub)


* [Apicurio Demo](http://localhost:8888/dashboard)

Ce repository synchronise les fichiers de `schemas/` vers Apicurio Registry.

## Structure attendue

Les chemins doivent respecter ce format :

`schemas/<domain>/<category>/<artifact-file>`

Exemples :
- `schemas/billing/asyncapi/order-events.yaml`
- `schemas/claims/graphql/claim.graphql`
- `schemas/claims/jsonschema/claim.json`

Catégories actuellement prises en charge dans le repo :
- `asyncapi`
- `graphql`
- `jsonschema`
- `openapi`
- `avro`
- `protobuf`
- `wsdl`
- `xsd`
- `xml`

Le script mappe automatiquement :
- `groupId = <APICURIO_GROUP_PREFIX><domain>-<category>`
- `artifactId = nom de fichier sans extension`
- `artifactType` basé sur `category` ou l’extension

Correspondance par défaut :
- `asyncapi` -> `ASYNCAPI`
- `graphql` -> `GRAPHQL`
- `jsonschema` -> `JSON`
- `openapi` -> `OPENAPI`
- `avro` -> `AVRO`
- `protobuf` -> `PROTOBUF`
- `wsdl` -> `WSDL`
- `xsd` -> `XSD`
- `xml` -> `XML`

## Utiliser `catalog/` comme lien Git -> Apicurio

Le catalog permet de surcharger le mapping automatique avec un mapping explicite.

Ordre de priorité :
1. `catalog/<domain>.csv` (ex: `catalog/billing.csv`)
2. `catalog/index.csv` (fallback global)

### Génération automatique des CSV

Le script `scripts/generate-catalog.sh` génère automatiquement :
- `catalog/index.csv`
- `catalog/<domain>.csv` pour chaque domaine trouvé sous `schemas/`

Commande :

```bash
chmod +x scripts/generate-catalog.sh
./scripts/generate-catalog.sh
```

Avec chemins personnalisés :

```bash
./scripts/generate-catalog.sh <schemas_dir> <catalog_dir>
```

Exemple :

```bash
./scripts/generate-catalog.sh schemas catalog
```

Bonnes pratiques :
- relancer la génération après ajout/renommage/suppression de schémas
- committer les CSV générés pour garder la traçabilité Git

Format :

`schema_path,group_id,artifact_id,artifact_type`

Exemple :

`schemas/billing/asyncapi/billing-events.yaml,billing-asyncapi,billing-events,ASYNCAPI`

Règles :
- `schema_path` doit pointer vers un fichier sous `schemas/`
- `artifact_type` doit correspondre à un type Apicurio (ex: `ASYNCAPI`, `GRAPHQL`, `JSON`, `AVRO`, `PROTOBUF`)
- si une entrée existe dans `catalog/index.csv`, elle est prioritaire sur le mapping auto
- si une entrée existe dans `catalog/<domain>.csv`, elle est prioritaire sur `catalog/index.csv`
- si `catalog/**` change, le workflow force une synchronisation complète de `schemas/**`

Avant publication, le script compare le contenu local avec la dernière version dans Apicurio :
- si identique: `skip` (pas de nouvelle version)
- si différent: création ou mise à jour de l’artifact
- en `DRY_RUN=true`: affiche l’action (`Create`, `Update`, `skip`) sans publier

## Variables d'environnement

### Obligatoires
- `APICURIO_URL` (ex: `https://apicurio.example.com`)

### Authentification
- `APICURIO_AUTH_TYPE` : `token` (défaut), `basic`, `none`

Si `token` :
- `APICURIO_TOKEN`

Si `basic` :
- `APICURIO_USERNAME`
- `APICURIO_PASSWORD`

### Optionnelles
- `APICURIO_GROUP_PREFIX` (ex: `prod-`)
- `CHANGED_FILES` (liste de fichiers, utilisée par GitHub Actions)
- `CATALOG_DIR` (défaut: `catalog`)
- `CATALOG_FILE` (défaut: `catalog/index.csv`)
- `DRY_RUN` (`true/false`, défaut: `false`)

## GitHub Actions

Le workflow `.github/workflows/apicurio-sync.yml` lance la sync sur push (`main`/`master`) pour les changements sous `schemas/**`.

Secrets GitHub à créer :
- `APICURIO_URL`
- `APICURIO_AUTH_TYPE` (optionnel, défaut `token`)
- `APICURIO_TOKEN` (si auth token)
- `APICURIO_USERNAME` / `APICURIO_PASSWORD` (si auth basic)
- `APICURIO_GROUP_PREFIX` (optionnel)

## Docker Compose

Le fichier [docker-compose.yaml](docker-compose.yaml) démarre une stack locale complète pour la démo :
- PostgreSQL
- Apicurio Registry
- Apicurio Registry UI

Démarrage :

```bash
docker compose up -d
```

URLs utiles :
- API Registry : `http://localhost:8080/apis/registry/v3`
- UI Registry : `http://localhost:8888`
- PostgreSQL : `localhost:5432`

Arrêt et nettoyage :

```bash
docker compose down
docker compose down -v
```

Pour utiliser cette stack avec les scripts locaux, configure `.env` ainsi :

```bash
APICURIO_URL="http://localhost:8080"
APICURIO_AUTH_TYPE="none"
DRY_RUN="false"
```

## Exécution locale

Option recommandée avec fichier `.env` :

```bash
cp .env.exemple .env
chmod +x scripts/run-local.sh
./scripts/run-local.sh
```

Le script `scripts/run-local.sh` :
- charge `.env` (ou `ENV_FILE=/chemin/vers/fichier.env`)
- génère les fichiers `catalog/*.csv`
- lance la synchronisation locale

Option manuelle :

```bash
chmod +x scripts/sync-to-apicurio.sh build.sh
./scripts/generate-catalog.sh
APICURIO_URL="https://apicurio.example.com" \
APICURIO_TOKEN="xxx" \
./build.sh

DRY_RUN=true APICURIO_URL="https://apicurio.example.com" APICURIO_TOKEN="xxx" ./build.sh
```
