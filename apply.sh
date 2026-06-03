#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CVAT_DIR="${1:-.}"

if [ ! -f "$CVAT_DIR/docker-compose.yml" ]; then
    echo "Error: $CVAT_DIR/docker-compose.yml not found."
    echo "Usage: $0 /path/to/cvat"
    exit 1
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

# 3. Copy override and .env if not present
if [ ! -f "$CVAT_DIR/docker-compose.override.yml" ]; then
    cp "$SCRIPT_DIR/templates/docker-compose.override.yml" "$CVAT_DIR/"
    echo "  Created docker-compose.override.yml (edit the data path!)"
else
    echo "  docker-compose.override.yml already exists, skipping."
fi

if [ ! -f "$CVAT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/templates/.env.example" "$CVAT_DIR/.env"
    echo "  Created .env from template (edit your domain!)"
else
    echo "  .env already exists, skipping."
fi

echo ""
echo "Done! Next steps:"
echo "  1. Edit $CVAT_DIR/.env — set your domain"
echo "  2. Edit $CVAT_DIR/docker-compose.override.yml — set your data path"
echo "  3. Run: docker compose up -d"
