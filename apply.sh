#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
CVAT_DIR=""
DOMAIN=""
DATA_DIR=""
LAN_IP=""
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
    echo "  -i, --lan-ip IP        Set LAN IP for local network access (auto-detected if omitted)"
    echo "  -r, --revert           Revert all patches, restore localhost access"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 ../cvat --domain cvat.example.com --data-dir /data/cvat"
    echo "  $0 ../cvat -d cvat.example.com -D /data/cvat --lan-ip 192.168.2.88"
    echo "  $0 ../cvat --revert"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage ;;
        -d|--domain)  DOMAIN="$2";  shift 2 ;;
        -D|--data-dir) DATA_DIR="$2"; shift 2 ;;
        -i|--lan-ip)  LAN_IP="$2"; shift 2 ;;
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

# Normalize: remove trailing slash from DATA_DIR
DATA_DIR="${DATA_DIR%/}"

# Auto-detect LAN IP if not specified
if [ -z "$LAN_IP" ]; then
    LAN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)
    if [ -z "$LAN_IP" ]; then
        LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    fi
    if [ -n "$LAN_IP" ]; then
        echo "Auto-detected LAN IP: $LAN_IP"
    else
        echo "Warning: Could not auto-detect LAN IP. Local network access will not be configured."
        echo "  Use --lan-ip to set manually."
    fi
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

    # 2. Remove LAN IP from Traefik routing rules
    if grep -q "|| Host(\`" "$CVAT_DIR/docker-compose.yml"; then
        # cvat_server: (Host(`domain`) || Host(`ip`)) -> Host(`domain`)
        sed -i 's#(Host(`${CVAT_HOST:-localhost}`) || Host(`[^`]*`))#Host(`${CVAT_HOST:-localhost}`)#' "$CVAT_DIR/docker-compose.yml"
        # cvat_ui: Host(`domain`) || Host(`ip`) -> Host(`domain`)
        sed -i '/traefik.http.routers.cvat-ui.rule:/s#Host(`${CVAT_HOST:-localhost}`) || Host(`[^`]*`)#Host(`${CVAT_HOST:-localhost}`)#' "$CVAT_DIR/docker-compose.yml"
        echo "  Removed LAN IP from Traefik routing rules"
    fi

    # 3. Clean override (keep data volume, remove tunnel config)
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

    # 4. Remove .env
    if [ -f "$CVAT_DIR/.env" ]; then
        rm -f "$CVAT_DIR/.env"
        echo "  Removed .env"
    fi

    # 5. Remove cloudflare_tunnel.py
    if [ -f "$CVAT_DIR/cvat/settings/cloudflare_tunnel.py" ]; then
        rm -f "$CVAT_DIR/cvat/settings/cloudflare_tunnel.py"
        echo "  Removed cvat/settings/cloudflare_tunnel.py"
    fi

    # 6. Remove traefik rules
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

# 3. Add LAN IP to Traefik routing rules (allows local network access)
if [ -n "$LAN_IP" ]; then
    # cvat_server: Host(`domain`) -> (Host(`domain`) || Host(`ip`))
    if grep -q "Host(\`${LAN_IP}\`)" "$CVAT_DIR/docker-compose.yml"; then
        echo "  LAN IP ($LAN_IP) already in cvat_server routing, skipping."
    else
        sed -i 's#Host(`${CVAT_HOST:-localhost}`) &&#(Host(`${CVAT_HOST:-localhost}`) || Host(`'"${LAN_IP}"'`)) \&\&#' "$CVAT_DIR/docker-compose.yml"
        echo "  Added LAN IP ($LAN_IP) to cvat_server routing"
    fi

    # cvat_ui: Host(`domain`) -> Host(`domain`) || Host(`ip`)
    if grep -A1 "traefik.http.routers.cvat-ui.rule:" "$CVAT_DIR/docker-compose.yml" | grep -q "Host(\`${LAN_IP}\`)"; then
        echo "  LAN IP ($LAN_IP) already in cvat_ui routing, skipping."
    else
        sed -i '/traefik.http.routers.cvat-ui.rule:/s#Host(`${CVAT_HOST:-localhost}`)#Host(`${CVAT_HOST:-localhost}`) || Host(`'"${LAN_IP}"'`)#' "$CVAT_DIR/docker-compose.yml"
        echo "  Added LAN IP ($LAN_IP) to cvat_ui routing"
    fi
fi

# 4. Create docker-compose.override.yml
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

# 5. Create .env
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
