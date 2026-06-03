#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
CVAT_DIR=""
DOMAIN=""
DATA_DIR=""
REVERT=false

usage() {
    echo "Usage: $0 <cvat_path> [options]"
    echo ""
    echo "Arguments:"
    echo "  <cvat_path>            Path to CVAT repository (required)"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN    Set CVAT domain (e.g. cvat.example.com)"
    echo "  -D, --data-dir DIR     Set host data directory for cvat_share volume"
    echo "  -r, --revert           Revert all patches, restore localhost access"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 ../cvat --domain cvat.example.com --data-dir /data/cvat"
    echo "  $0 ../cvat -d cvat.example.com -D /data/cvat"
    echo "  $0 ../cvat --revert"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage ;;
        -d|--domain)  DOMAIN="$2";  shift 2 ;;
        -D|--data-dir) DATA_DIR="$2"; shift 2 ;;
        -r|--revert)  REVERT=true; shift ;;
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

# ========== Revert mode ==========
if [ "$REVERT" = true ]; then
    echo ""
    echo "Reverting Cloudflare Tunnel patches..."

    # 1. Reverse the docker-compose.yml patch
    if grep -q "force-https@file" "$CVAT_DIR/docker-compose.yml"; then
        patch -R -p1 -d "$CVAT_DIR" < "$SCRIPT_DIR/patches/docker-compose.yml.patch"
        echo "  Reverted docker-compose.yml"
    else
        echo "  docker-compose.yml not patched, skipping."
    fi

    # 2. Clean override (keep data volume, remove tunnel config)
    if [ -f "$CVAT_DIR/docker-compose.override.yml" ]; then
        # Extract data device path if present
        data_device=""
        data_device=$(grep "device:" "$CVAT_DIR/docker-compose.override.yml" | awk '{print $2}')
        if [ -n "$data_device" ] && [ "$data_device" != "/path/to/your/data" ]; then
            # Has real data dir: generate minimal override with only data volume
            cat > "$CVAT_DIR/docker-compose.override.yml" << OVERRIDE
services:
  cvat_server:
    volumes:
      - cvat_share:/home/django/share:ro
  cvat_worker_import:
    volumes:
      - cvat_share:/home/django/share:ro
  cvat_worker_export:
    volumes:
      - cvat_share:/home/django/share:ro
  cvat_worker_annotation:
    volumes:
      - cvat_share:/home/django/share:ro
  cvat_worker_chunks:
    volumes:
      - cvat_share:/home/django/share:ro
  cvat_worker_utils:
    volumes:
      - cvat_share:/home/django/share:ro

volumes:
  cvat_share:
    driver_opts:
      type: none
      device: $data_device
      o: bind
OVERRIDE
            echo "  Cleaned docker-compose.override.yml (kept data volume: $data_device)"
        else
            rm -f "$CVAT_DIR/docker-compose.override.yml"
            echo "  Removed docker-compose.override.yml"
        fi
    fi

    # 3. Remove .env
    if [ -f "$CVAT_DIR/.env" ]; then
        rm -f "$CVAT_DIR/.env"
        echo "  Removed .env"
    fi

    # 4. Remove cloudflare_tunnel.py
    if [ -f "$CVAT_DIR/cvat/settings/cloudflare_tunnel.py" ]; then
        rm -f "$CVAT_DIR/cvat/settings/cloudflare_tunnel.py"
        echo "  Removed cvat/settings/cloudflare_tunnel.py"
    fi

    # 5. Remove traefik rules
    if [ -f "$CVAT_DIR/traefik/rules/force-https.yml" ]; then
        rm -f "$CVAT_DIR/traefik/rules/force-https.yml"
        rmdir "$CVAT_DIR/traefik/rules" 2>/dev/null || true
        rmdir "$CVAT_DIR/traefik" 2>/dev/null || true
        echo "  Removed traefik/rules/force-https.yml"
    fi

    echo ""
    echo "Done! CVAT is restored to localhost access."
    echo "Run: cd $CVAT_DIR && docker compose up -d"
    exit 0
fi

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
