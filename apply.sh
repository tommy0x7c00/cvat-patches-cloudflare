#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
CVAT_DIR=""
DOMAIN=""
DATA_DIR=""

usage() {
    echo "Usage: $0 <cvat_path> [options]"
    echo ""
    echo "Arguments:"
    echo "  <cvat_path>            Path to CVAT repository (required)"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN    Set CVAT domain (e.g. cvat.example.com)"
    echo "  -D, --data-dir DIR     Set host data directory for cvat_share volume"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 ../cvat --domain cvat.example.com --data-dir /data/cvat"
    echo "  $0 ../cvat -d cvat.example.com -D /data/cvat"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage ;;
        -d|--domain)  DOMAIN="$2";  shift 2 ;;
        -D|--data-dir) DATA_DIR="$2"; shift 2 ;;
        -*)           echo "Error: Unknown option $1"; usage ;;
        *)
            if [ -z "$CVAT_DIR" ]; then
                CVAT_DIR="$1"; shift
            else
                echo "Error: Unexpected argument $1"; usage
            fi
            ;;
    esac
done

if [ -z "$CVAT_DIR" ]; then
    echo "Error: <cvat_path> is required."
    usage
fi

if [ ! -f "$CVAT_DIR/docker-compose.yml" ]; then
    echo "Error: $CVAT_DIR/docker-compose.yml not found."
    usage
fi

echo "Applying Cloudflare Tunnel patches to: $CVAT_DIR"

# 1. Copy new files
cp "$SCRIPT_DIR/patches/cvat/settings/cloudflare_tunnel.py" "$CVAT_DIR/cvat/settings/"
mkdir -p "$CVAT_DIR/traefik/rules"
cp "$SCRIPT_DIR/patches/traefik/rules/force-https.yml" "$CVAT_DIR/traefik/rules/"

# 2. Patch docker-compose.yml (add traefik middleware label)
if grep -q "force-https@file" "$CVAT_DIR/docker-compose.yml"; then
    echo "  docker-compose.yml already patched, skipping."
else
    patch -p1 -d "$CVAT_DIR" < "$SCRIPT_DIR/patches/docker-compose.yml.patch"
    echo "  Patched docker-compose.yml"
fi

# 3. Create docker-compose.override.yml
if [ -n "$DATA_DIR" ]; then
    # --data-dir specified: always generate (overwrite if needed)
    sed "s|/path/to/your/data|${DATA_DIR}|g" \
        "$SCRIPT_DIR/templates/docker-compose.override.yml" > "$CVAT_DIR/docker-compose.override.yml"
    echo "  Created docker-compose.override.yml (data dir: $DATA_DIR)"
elif [ ! -f "$CVAT_DIR/docker-compose.override.yml" ]; then
    cp "$SCRIPT_DIR/templates/docker-compose.override.yml" "$CVAT_DIR/"
    echo "  Created docker-compose.override.yml (edit the data path!)"
else
    echo "  docker-compose.override.yml already exists, skipping."
fi

# 4. Create .env
if [ -n "$DOMAIN" ]; then
    # --domain specified: always generate (overwrite if needed)
    sed -e "s|your-domain.com|${DOMAIN}|g" \
        "$SCRIPT_DIR/templates/.env.example" > "$CVAT_DIR/.env"
    echo "  Created .env (domain: $DOMAIN)"
elif [ ! -f "$CVAT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/templates/.env.example" "$CVAT_DIR/.env"
    echo "  Created .env from template (edit your domain!)"
else
    echo "  .env already exists, skipping."
fi

echo ""
echo "Done!"
if [ -z "$DOMAIN" ] || [ -z "$DATA_DIR" ]; then
    echo "Remaining manual steps:"
    [ -z "$DOMAIN" ]  && echo "  - Edit $CVAT_DIR/.env — set your domain"
    [ -z "$DATA_DIR" ] && echo "  - Edit $CVAT_DIR/docker-compose.override.yml — set your data path"
fi
echo "Run: cd $CVAT_DIR && docker compose up -d"
