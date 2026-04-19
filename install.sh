#!/bin/bash

# ----------------------------------------------------------------------------
# Dokploy installer — disesuaikan untuk repository lokal ini.
#
# Berbeda dari script resmi `https://dokploy.com/install.sh`, varian ini
# secara default akan **membangun image Dokploy dari source di repo ini**
# (Dockerfile pada root repository), sehingga dapat menyertakan modifikasi
# lokal (mis. perubahan kode atau adendum lisensi).
#
# Variabel lingkungan yang dikenali:
#   DOKPLOY_INSTALL_MODE   build|registry  (default: build)
#                          - build    : docker build dari Dockerfile lokal
#                          - registry : tarik dari Docker Hub (perilaku lama)
#   DOKPLOY_VERSION        tag/versi yang dipakai. Jika kosong:
#                          - mode build    -> baca apps/dokploy/package.json
#                          - mode registry -> deteksi rilis terbaru di GitHub
#   DOKPLOY_IMAGE          override penuh nama:tag image (mis. ghcr.io/x/y:z)
#   ADVERTISE_ADDR         alamat IP untuk Swarm advertise
#   DOCKER_SWARM_INIT_ARGS argumen tambahan utk `docker swarm init`
#
# Cara pakai:
#   sudo bash install.sh                       # build & install dari repo lokal
#   sudo DOKPLOY_INSTALL_MODE=registry bash install.sh
#   sudo bash install.sh update                # update sesuai mode aktif
# ----------------------------------------------------------------------------

# Lokasi script -> dipakai sebagai konteks build.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

DEFAULT_INSTALL_MODE="build"
INSTALL_MODE="${DOKPLOY_INSTALL_MODE:-$DEFAULT_INSTALL_MODE}"

case "$INSTALL_MODE" in
    build|registry) ;;
    *)
        echo "Error: DOKPLOY_INSTALL_MODE harus 'build' atau 'registry' (got: '$INSTALL_MODE')" >&2
        exit 1
        ;;
esac

detect_version() {
    local version="${DOKPLOY_VERSION}"

    # Mode build -> versi diambil dari package.json lokal (sumber kebenaran).
    if [ -z "$version" ] && [ "$INSTALL_MODE" = "build" ]; then
        if [ -f "$SCRIPT_DIR/apps/dokploy/package.json" ] && command -v node >/dev/null 2>&1; then
            version=$(node -p "require('$SCRIPT_DIR/apps/dokploy/package.json').version" 2>/dev/null)
            if [ -n "$version" ]; then
                echo "Versi terdeteksi dari apps/dokploy/package.json: $version" >&2
            fi
        fi
        # Fallback bila node tidak ada / file tak terbaca.
        if [ -z "$version" ]; then
            version="local"
            echo "Tidak bisa membaca versi dari package.json, memakai tag fallback: $version" >&2
        fi
    fi

    # Mode registry (atau fallback) -> deteksi rilis stabil dari GitHub.
    if [ -z "$version" ]; then
        echo "Mendeteksi versi stabil terbaru dari GitHub..." >&2
        version=$(curl -fsSL -o /dev/null -w '%{url_effective}\n' \
            https://github.com/dokploy/dokploy/releases/latest 2>/dev/null | \
            sed 's#.*/tag/##')
        if [ -z "$version" ]; then
            echo "Warning: gagal mendeteksi versi terbaru, memakai 'latest'" >&2
            version="latest"
        else
            echo "Versi stabil terbaru: $version" >&2
        fi
    fi

    echo "$version"
}

# Deteksi LXC (Proxmox) untuk kompatibilitas service discovery.
is_proxmox_lxc() {
    if [ -n "$container" ] && [ "$container" = "lxc" ]; then
        return 0
    fi
    if grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
        return 0
    fi
    return 1
}

generate_random_password() {
    local password=""

    if command -v openssl >/dev/null 2>&1; then
        password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    elif [ -r /dev/urandom ]; then
        password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    else
        if command -v sha256sum >/dev/null 2>&1; then
            password=$(date +%s%N | sha256sum | base64 | head -c 32)
        elif command -v shasum >/dev/null 2>&1; then
            password=$(date +%s%N | shasum -a 256 | base64 | head -c 32)
        else
            password=$(echo "$(date +%s%N)-$(hostname)-$$-$RANDOM" | base64 | tr -d "=+/" | head -c 32)
        fi
    fi

    if [ -z "$password" ] || [ ${#password} -lt 20 ]; then
        echo "Error: Failed to generate random password" >&2
        exit 1
    fi

    echo "$password"
}

# Resolve nama:tag image yang akan dipakai oleh service Dokploy.
resolve_image() {
    local version="$1"

    if [ -n "$DOKPLOY_IMAGE" ]; then
        echo "$DOKPLOY_IMAGE"
        return
    fi

    if [ "$INSTALL_MODE" = "build" ]; then
        # Tag image lokal supaya tidak bentrok dengan image registry.
        echo "dokploy/dokploy:local-${version}"
    else
        echo "dokploy/dokploy:${version}"
    fi
}

# Build image dari Dockerfile lokal di repo ini.
build_local_image() {
    local image_tag="$1"

    if [ ! -f "$SCRIPT_DIR/Dockerfile" ]; then
        echo "Error: Dockerfile tidak ditemukan di $SCRIPT_DIR" >&2
        echo "Jalankan script dari root repository, atau pakai DOKPLOY_INSTALL_MODE=registry." >&2
        exit 1
    fi

    # `Dockerfile` melakukan COPY .env.production -> ./.env saat build.
    if [ ! -f "$SCRIPT_DIR/.env.production" ]; then
        echo "Membuat .env.production minimal supaya build tidak gagal..."
        cat > "$SCRIPT_DIR/.env.production" <<'EOF'
NODE_ENV=production
PORT=3000
EOF
    fi

    echo "Membangun image Dokploy lokal: $image_tag"
    echo "Konteks build: $SCRIPT_DIR"
    docker build \
        --pull \
        --tag "$image_tag" \
        --file "$SCRIPT_DIR/Dockerfile" \
        "$SCRIPT_DIR"

    if [ $? -ne 0 ]; then
        echo "Error: docker build gagal" >&2
        exit 1
    fi
}

install_dokploy() {
    VERSION_TAG=$(detect_version)
    DOCKER_IMAGE=$(resolve_image "$VERSION_TAG")

    echo "Mode instalasi : ${INSTALL_MODE}"
    echo "Versi          : ${VERSION_TAG}"
    echo "Image target   : ${DOCKER_IMAGE}"

    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" >&2
        exit 1
    fi

    if [ "$(uname)" = "Darwin" ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    if [ -f /.dockerenv ]; then
        echo "This script must be run on Linux" >&2
        exit 1
    fi

    if ss -tulnp | grep ':80 ' >/dev/null; then
        echo "Error: something is already running on port 80" >&2
        exit 1
    fi

    if ss -tulnp | grep ':443 ' >/dev/null; then
        echo "Error: something is already running on port 443" >&2
        exit 1
    fi

    if ss -tulnp | grep ':3000 ' >/dev/null; then
        echo "Error: something is already running on port 3000" >&2
        echo "Dokploy requires port 3000 to be available. Please stop any service using this port." >&2
        exit 1
    fi

    command_exists() {
      command -v "$@" > /dev/null 2>&1
    }

    if command_exists docker; then
      echo "Docker already installed"
    else
      curl -sSL https://get.docker.com | sh -s -- --version 28.5.0
    fi

    # Build image lokal sebelum init swarm (build hanya butuh docker engine).
    if [ "$INSTALL_MODE" = "build" ]; then
        build_local_image "$DOCKER_IMAGE"
    fi

    endpoint_mode=""
    if is_proxmox_lxc; then
        echo "⚠️ WARNING: Detected Proxmox LXC container environment!"
        echo "Adding --endpoint-mode dnsrr to Docker services for LXC compatibility."
        echo "This may affect service discovery but is required for LXC containers."
        echo ""
        endpoint_mode="--endpoint-mode dnsrr"
        echo "Waiting for 5 seconds before continuing..."
        sleep 5
    fi


    docker swarm leave --force 2>/dev/null

    get_ip() {
        local ip=""

        ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null)

        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
        fi

        if [ -z "$ip" ]; then
            ip=$(curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
        fi

        if [ -z "$ip" ]; then
            ip=$(curl -6s --connect-timeout 5 https://ifconfig.io 2>/dev/null)

            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://icanhazip.com 2>/dev/null)
            fi

            if [ -z "$ip" ]; then
                ip=$(curl -6s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null)
            fi
        fi

        if [ -z "$ip" ]; then
            echo "Error: Could not determine server IP address automatically (neither IPv4 nor IPv6)." >&2
            echo "Please set the ADVERTISE_ADDR environment variable manually." >&2
            echo "Example: export ADVERTISE_ADDR=<your-server-ip>" >&2
            exit 1
        fi

        echo "$ip"
    }

    get_private_ip() {
        ip addr show | grep -E "inet (192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)" | head -n1 | awk '{print $2}' | cut -d/ -f1
    }

    advertise_addr="${ADVERTISE_ADDR:-$(get_private_ip)}"

    if [ -z "$advertise_addr" ]; then
        echo "ERROR: We couldn't find a private IP address."
        echo "Please set the ADVERTISE_ADDR environment variable manually."
        echo "Example: export ADVERTISE_ADDR=192.168.1.100"
        exit 1
    fi
    echo "Using advertise address: $advertise_addr"

    # Argumen tambahan untuk `docker swarm init` via DOCKER_SWARM_INIT_ARGS.
    # Berguna untuk menghindari overlap CIDR dengan VPC cloud (mis. AWS).
    swarm_init_args="${DOCKER_SWARM_INIT_ARGS:-}"

    if [ -n "$swarm_init_args" ]; then
        echo "Using custom swarm init arguments: $swarm_init_args"
        docker swarm init --advertise-addr $advertise_addr $swarm_init_args
    else
        docker swarm init --advertise-addr $advertise_addr
    fi

     if [ $? -ne 0 ]; then
        echo "Error: Failed to initialize Docker Swarm" >&2
        exit 1
    fi

    echo "Swarm initialized"

    docker network rm -f dokploy-network 2>/dev/null
    docker network create --driver overlay --attachable dokploy-network

    echo "Network created"

    mkdir -p /etc/dokploy

    chmod 777 /etc/dokploy

    POSTGRES_PASSWORD=$(generate_random_password)

    # Simpan password sebagai Docker Secret (terenkripsi pada raft store Swarm).
    echo "$POSTGRES_PASSWORD" | docker secret create dokploy_postgres_password - 2>/dev/null || true

    echo "Generated secure database credentials (stored in Docker Secrets)"

    docker service create \
    --name dokploy-postgres \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --env POSTGRES_USER=dokploy \
    --env POSTGRES_DB=dokploy \
    --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
    --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
    --mount type=volume,source=dokploy-postgres,target=/var/lib/postgresql/data \
    $endpoint_mode \
    postgres:16

    docker service create \
    --name dokploy-redis \
    --constraint 'node.role==manager' \
    --network dokploy-network \
    --mount type=volume,source=dokploy-redis,target=/data \
    $endpoint_mode \
    redis:7

    # RELEASE_TAG dipakai oleh aplikasi untuk auto-update / display versi.
    release_tag_env=""
    if [ "$INSTALL_MODE" = "build" ]; then
        # Build lokal: jangan biarkan UI mencoba auto-update ke registry.
        release_tag_env="-e RELEASE_TAG=local"
    elif [[ "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        release_tag_env="-e RELEASE_TAG=latest"
    elif [ "$VERSION_TAG" != "latest" ]; then
        release_tag_env="-e RELEASE_TAG=$VERSION_TAG"
    fi

    docker service create \
      --name dokploy \
      --replicas 1 \
      --network dokploy-network \
      --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
      --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
      --mount type=volume,source=dokploy,target=/root/.docker \
      --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
      --publish published=3000,target=3000,mode=host \
      --update-parallelism 1 \
      --update-order stop-first \
      --constraint 'node.role == manager' \
      $endpoint_mode \
      $release_tag_env \
      -e ADVERTISE_ADDR=$advertise_addr \
      -e POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
      $DOCKER_IMAGE

    sleep 4

    docker run -d \
        --name dokploy-traefik \
        --restart always \
        -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
        -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -p 80:80/tcp \
        -p 443:443/tcp \
        -p 443:443/udp \
        traefik:v3.6.7

    docker network connect dokploy-network dokploy-traefik


    # Alternatif (Swarm-managed Traefik):
    #   docker service create \
    #     --name dokploy-traefik \
    #     --constraint 'node.role==manager' \
    #     --network dokploy-network \
    #     --mount type=bind,source=/etc/dokploy/traefik/traefik.yml,target=/etc/traefik/traefik.yml \
    #     --mount type=bind,source=/etc/dokploy/traefik/dynamic,target=/etc/dokploy/traefik/dynamic \
    #     --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    #     --publish mode=host,published=443,target=443 \
    #     --publish mode=host,published=80,target=80 \
    #     --publish mode=host,published=443,target=443,protocol=udp \
    #     traefik:v3.6.7

    GREEN="\033[0;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[0;34m"
    NC="\033[0m" # No Color

    format_ip_for_url() {
        local ip="$1"
        if echo "$ip" | grep -q ':'; then
            echo "[${ip}]"
        else
            echo "${ip}"
        fi
    }

    public_ip="${ADVERTISE_ADDR:-$(get_ip)}"
    formatted_addr=$(format_ip_for_url "$public_ip")
    echo ""
    printf "${GREEN}Congratulations, Dokploy is installed!${NC}\n"
    printf "${BLUE}Wait 15 seconds for the server to start${NC}\n"
    printf "${YELLOW}Please go to http://${formatted_addr}:3000${NC}\n\n"
}

update_dokploy() {
    VERSION_TAG=$(detect_version)
    DOCKER_IMAGE=$(resolve_image "$VERSION_TAG")

    echo "Mode update : ${INSTALL_MODE}"
    echo "Versi       : ${VERSION_TAG}"
    echo "Image       : ${DOCKER_IMAGE}"

    if [ "$INSTALL_MODE" = "build" ]; then
        build_local_image "$DOCKER_IMAGE"
    else
        docker pull "$DOCKER_IMAGE"
    fi

    docker service update --image "$DOCKER_IMAGE" dokploy

    echo "Dokploy has been updated to: ${DOCKER_IMAGE}"
}

if [ "$1" = "update" ]; then
    update_dokploy
else
    install_dokploy
fi
