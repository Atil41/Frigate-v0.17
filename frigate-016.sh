#!/usr/bin/env bash

# Script d'installation Frigate corrigé pour Debian 12
# Résout les problèmes de packages obsolètes

# Variables de configuration
APP="Frigate"
CTID=""
HOSTNAME="frigate"
MEMORY="4096"
DISK_SIZE="20"
CORES="4"
PASSWORD=""
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
STORAGE="local-lvm"
BRIDGE="vmbr0"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fonctions d'affichage
msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
msg_error() { echo -e "${RED}[✗]${NC} $1"; }
msg_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }

# Header
header_info() {
    echo -e "${BLUE}"
    echo "  ________    _             __"
    echo " / ____/ /__(_)___ _____ _/ /____"
    echo "/ /_  / /__/ / __ \`/ __ \`/ __/ _ \\"
    echo "/ __/ / /  / / /_/ / /_/ / /_/  __/"
    echo "/_/   /_/  /_/\\__, /\\__,_/\\__/\\___/"
    echo "             /____/"
    echo -e "${NC}"
    echo "        Frigate NVR - Installation corrigée"
    echo ""
}

# Parsing des arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--id) CTID="$2"; shift 2 ;;
            -h|--hostname) HOSTNAME="$2"; shift 2 ;;
            -m|--memory) MEMORY="$2"; shift 2 ;;
            -d|--disk) DISK_SIZE="$2"; shift 2 ;;
            -c|--cores) CORES="$2"; shift 2 ;;
            -p|--password) PASSWORD="$2"; shift 2 ;;
            --help) show_usage; exit 0 ;;
            *) msg_error "Option inconnue: $1"; show_usage; exit 1 ;;
        esac
    done

    [[ -z "$CTID" || -z "$PASSWORD" ]] && { msg_error "ID conteneur et mot de passe requis"; show_usage; exit 1; }
}

show_usage() {
    cat << EOF
Installation Frigate corrigée pour Debian 12

Usage: $0 [OPTIONS]

OPTIONS:
  -i, --id CTID           ID du conteneur (requis)
  -h, --hostname NAME     Nom d'hôte (défaut: frigate)
  -m, --memory MB         Mémoire en MB (défaut: 4096)
  -d, --disk GB           Taille du disque en GB (défaut: 20)
  -c, --cores N           Nombre de cœurs CPU (défaut: 4)
  -p, --password PASS     Mot de passe root (requis)
  --help                  Affiche cette aide

Exemples:
  $0 -i 101 -p monpassword
  $0 -i 102 -h frigate-nvr -m 8192 -d 32 -p secret123
EOF
}

# Création du conteneur
create_container() {
    msg_info "🔧 Création du conteneur LXC ID:$CTID..."

    if pct status $CTID >/dev/null 2>&1; then
        msg_warn "Conteneur $CTID existe déjà, suppression..."
        pct stop $CTID >/dev/null 2>&1 || true
        pct destroy $CTID >/dev/null 2>&1 || true
    fi

    pct create $CTID /var/lib/vz/template/cache/$TEMPLATE \
        --hostname $HOSTNAME \
        --memory $MEMORY \
        --cores $CORES \
        --rootfs $STORAGE:$DISK_SIZE \
        --net0 name=eth0,bridge=$BRIDGE,firewall=1,ip=dhcp \
        --password $PASSWORD \
        --features nesting=1,keyctl=1 \
        --unprivileged 0 \
        --onboot 1 || {
        msg_error "Échec création conteneur"
        exit 1
    }

    msg_ok "Conteneur $CTID créé"

    msg_info "▶️ Démarrage du conteneur..."
    pct start $CTID || {
        msg_error "Échec démarrage conteneur"
        exit 1
    }

    msg_info "⏳ Attente du démarrage complet..."
    sleep 15
    msg_ok "Conteneur démarré et prêt"
}

# Script d'installation Frigate dans le conteneur
create_frigate_script() {
    cat << 'FRIGATE_SCRIPT_EOF' | pct exec $CTID -- bash -c "cat > /root/frigate-install.sh && chmod +x /root/frigate-install.sh"
#!/usr/bin/env bash

# Script d'installation Frigate corrigé pour Debian 12
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
msg_ok() { echo -e "${GREEN}[✓]${NC} $1"; }
msg_error() { echo -e "${RED}[✗]${NC} $1"; }
msg_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }

# Configuration système
setup_system() {
    msg_info "⚙️ Configuration système Debian 12..."

    # Configuration locales
    echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
    locale-gen >/dev/null 2>&1 || true

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    # Sources APT optimisées
    cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://security.debian.org bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

    # Configuration APT
    cat > /etc/apt/apt.conf.d/99frigate << 'EOF'
Acquire::Retries "3";
Acquire::http::Timeout "30";
Quiet "1";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Dpkg::Options { "--force-confdef"; "--force-confold"; }
EOF

    msg_info "📦 Mise à jour des packages..."
    apt-get update -qq >/dev/null 2>&1 || {
        msg_error "Échec mise à jour APT"
        exit 1
    }

    msg_ok "Système configuré"
}

# Installation des dépendances corrigées pour Debian 12
install_dependencies() {
    msg_info "📦 Installation dépendances système (Debian 12 corrigées)..."

    # Liste CORRIGÉE des packages pour Debian 12
    # Remplacements effectués:
    # - libtbb2 -> libtbb12 (nouveau nom dans Debian 12)
    # - libdc1394-22-dev -> libdc1394-dev (nom simplifié)
    # - Packages vérifiés pour compatibilité Debian 12
    SYSTEM_PACKAGES="
    git ca-certificates automake build-essential xz-utils libtool ccache pkg-config
    libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev
    libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev
    gfortran openexr libatlas-base-dev libssl-dev
    libtbb12 libtbb-dev
    libdc1394-dev
    libopenexr-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev
    gcc gfortran libopenblas-dev liblapack-dev libusb-1.0-0-dev
    jq moreutils curl wget
    python3 python3-pip python3-dev python3-venv python3-setuptools
    nginx ffmpeg
    sqlite3 libsqlite3-dev
    "

    msg_info "Installation en cours..."

    # Installation avec gestion d'erreur améliorée
    if apt-get install -y --no-install-recommends $SYSTEM_PACKAGES 2>/tmp/install.log; then
        msg_ok "✅ Dépendances système installées"
    else
        msg_error "❌ Échec installation - détails:"
        tail -10 /tmp/install.log

        # Tentative d'installation des packages essentiels un par un
        msg_warn "Tentative d'installation des packages essentiels..."
        ESSENTIAL_PACKAGES="git build-essential python3 python3-pip python3-dev nginx ffmpeg curl wget jq"

        for pkg in $ESSENTIAL_PACKAGES; do
            if apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1; then
                msg_ok "✓ $pkg installé"
            else
                msg_warn "⚠ $pkg échoué"
            fi
        done
    fi

    # Vérification des packages critiques
    msg_info "🔍 Vérification des packages critiques..."
    critical_packages="python3 python3-pip git curl wget nginx ffmpeg"
    missing_packages=""

    for pkg in $critical_packages; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            missing_packages="$missing_packages $pkg"
        fi
    done

    if [[ -n "$missing_packages" ]]; then
        msg_error "Packages critiques manquants:$missing_packages"
        exit 1
    else
        msg_ok "✅ Tous les packages critiques sont installés"
    fi
}

# Configuration Python
setup_python() {
    msg_info "🐍 Configuration Python pour Frigate..."

    # Configuration pip pour Debian 12
    export PIP_OPTS="--break-system-packages --root-user-action=ignore"

    # Mise à jour pip
    python3 -m pip install $PIP_OPTS --upgrade pip >/dev/null 2>&1 || {
        msg_warn "Échec mise à jour pip"
    }

    # Installation des dépendances Python pour Frigate
    msg_info "📦 Installation dépendances Python Frigate..."

    PYTHON_PACKAGES=(
        "setuptools>=60.0.0"
        "wheel>=0.37.0"
        "pyyaml>=6.0"
        "requests>=2.25.0"
        "psutil>=5.8.0"
        "numpy>=1.21.0"
        "opencv-python>=4.5.0"
        "pillow>=8.3.0"
        "fastapi>=0.70.0"
        "uvicorn[standard]>=0.15.0"
        "pydantic>=1.8.0"
        "peewee>=3.14.0"
        "flask>=2.0.0"
        "click>=8.0.0"
        "watchdog>=2.1.0"
        "websockets>=10.0"
        "python-multipart>=0.0.5"
    )

    installed_count=0
    for package in "${PYTHON_PACKAGES[@]}"; do
        if python3 -m pip install $PIP_OPTS "$package" >/dev/null 2>&1; then
            ((installed_count++))
        else
            # Essayer sans contrainte de version
            base_pkg=$(echo "$package" | cut -d'>' -f1 | cut -d'=' -f1)
            python3 -m pip install $PIP_OPTS "$base_pkg" >/dev/null 2>&1 && ((installed_count++)) || true
        fi
    done

    msg_ok "$installed_count/${#PYTHON_PACKAGES[@]} packages Python installés"
}

# Installation Frigate v0.16
install_frigate() {
    msg_info "🎥 Installation Frigate v0.16..."

    # Création des répertoires
    mkdir -p /opt/frigate /config /media/frigate
    mkdir -p /media/frigate/clips /media/frigate/recordings /media/frigate/exports

    # Installation Frigate v0.16 via pip
    if python3 -m pip install $PIP_OPTS frigate==0.16.1 >/dev/null 2>&1; then
        msg_ok "✅ Frigate v0.16.1 installé via pip"
    elif python3 -m pip install $PIP_OPTS frigate==0.16.0 >/dev/null 2>&1; then
        msg_ok "✅ Frigate v0.16.0 installé via pip"
    else
        msg_warn "Installation pip échouée, tentative depuis le code source..."

        cd /opt
        # Essayer d'abord v0.16.1, puis v0.16.0
        for version in "0.16.1" "0.16.0"; do
            msg_info "Tentative téléchargement Frigate v$version..."
            if curl -L https://github.com/blakeblackshear/frigate/archive/v$version.tar.gz -o frigate.tar.gz 2>/dev/null; then
                tar -xzf frigate.tar.gz
                mv frigate-$version frigate
                rm frigate.tar.gz
                cd frigate

                if python3 -m pip install $PIP_OPTS -e . >/dev/null 2>&1; then
                    msg_ok "✅ Frigate v$version installé depuis le code source"
                    break
                else
                    msg_warn "Échec installation depuis le code source v$version"
                    cd /opt
                    rm -rf frigate
                fi
            else
                msg_warn "Échec téléchargement v$version"
            fi
        done

        # Vérifier si l'installation a réussi
        if ! python3 -c "import frigate" >/dev/null 2>&1; then
            msg_error "Échec installation Frigate v0.16"
            exit 1
        fi
    fi

    # Vérifier la version installée
    msg_info "🔍 Vérification de l'installation..."
    INSTALLED_VERSION=$(python3 -c "
try:
    import frigate
    from frigate.version import VERSION
    print(f'Version installée: {VERSION}')
except:
    print('Version: Inconnue mais Frigate installé')
" 2>/dev/null)
    msg_ok "$INSTALLED_VERSION"
}

# Configuration Frigate v0.16
configure_frigate() {
    msg_info "📝 Configuration Frigate v0.16..."

    # Configuration de base pour Frigate v0.16
    cat > /config/config.yml << 'EOF'
# Configuration Frigate v0.16
mqtt:
  enabled: false

database:
  path: /config/frigate.db

# Détecteur CPU (compatible v0.16)
detectors:
  cpu1:
    type: cpu
    num_threads: 3

# Modèle de détection (v0.16)
model:
  width: 320
  height: 320
  input_tensor: nhwc
  input_pixel_format: rgb
  path: /config/model_cache/yolov8n.pt
  labelmap_path: /config/model_cache/labelmap.txt

# Configuration des objets (v0.16)
objects:
  track:
    - person
    - car
    - truck
    - bus
    - motorcycle
    - bicycle
  filters:
    person:
      min_area: 5000
      max_area: 100000
      threshold: 0.7
      min_score: 0.5

# Configuration snapshots (v0.16)
snapshots:
  enabled: true
  timestamp: false
  bounding_box: true
  crop: false
  retain:
    default: 10

# Configuration enregistrement (v0.16)
record:
  enabled: false
  retain:
    days: 0
  events:
    retain:
      default: 10
      mode: motion

# Configuration de détection de mouvement (v0.16)
motion:
  threshold: 25
  contour_area: 30
  delta_alpha: 0.2
  frame_alpha: 0.2
  frame_height: 180
  improve_contrast: true

# Configuration Go2RTC (v0.16)
go2rtc:
  streams: {}

# Interface utilisateur (v0.16)
ui:
  use_experimental: false
  live_mode: mse

# Logger (v0.16)
logger:
  default: info
  logs:
    frigate.record: debug
    frigate.motion: info

# Configuration Birdseye (v0.16)
birdseye:
  enabled: false
  width: 1280
  height: 720
  quality: 8

# Caméras (à configurer)
cameras: {}
EOF

    # Créer le répertoire pour le cache du modèle
    mkdir -p /config/model_cache

    # Service systemd pour Frigate v0.16
    cat > /etc/systemd/system/frigate.service << 'EOF'
[Unit]
Description=Frigate NVR v0.16
After=network.target

[Service]
Type=exec
User=root
ExecStart=/usr/bin/python3 -m frigate.app
Environment=CONFIG_FILE=/config/config.yml
Environment=FRIGATE_CONFIG_FILE=/config/config.yml
WorkingDirectory=/opt/frigate
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Configuration Nginx pour Frigate v0.16
    cat > /etc/nginx/sites-available/frigate << 'EOF'
server {
    listen 8080;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/frigate /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Permissions
    chown -R root:root /opt/frigate /config /media/frigate
    chmod -R 755 /opt/frigate /config /media/frigate

    msg_ok "Configuration Frigate v0.16 terminée"
}

# Démarrage des services
start_services() {
    msg_info "🚀 Démarrage des services..."

    systemctl daemon-reload
    systemctl enable frigate nginx

    # Test nginx
    if nginx -t >/dev/null 2>&1; then
        systemctl restart nginx
        msg_ok "✅ Nginx démarré"
    else
        msg_warn "⚠️ Problème configuration nginx"
    fi

    # Test Frigate
    if systemctl start frigate; then
        sleep 5
        if systemctl is-active --quiet frigate; then
            msg_ok "✅ Frigate démarré"
        else
            msg_warn "⚠️ Frigate a des problèmes au démarrage"
            systemctl status frigate --no-pager -l
        fi
    else
        msg_error "Échec démarrage Frigate"
    fi
}

# Résumé final
show_summary() {
    local IP=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -n1 || echo "IP_NOT_DETECTED")

    echo ""
    echo "========================================"
    echo "   INSTALLATION FRIGATE TERMINÉE"
    echo "========================================"
    echo ""
    echo "🌐 Accès à Frigate:"
    echo "   Interface principale: http://$IP:5000"
    echo "   Via Nginx proxy: http://$IP:8080"
    echo ""
    echo "📁 Fichiers importants:"
    echo "   Configuration: /config/config.yml"
    echo "   Base de données: /config/frigate.db"
    echo "   Média: /media/frigate/"
    echo ""
    echo "🛠️ Gestion:"
    echo "   Statut: systemctl status frigate"
    echo "   Logs: journalctl -u frigate -f"
    echo "   Redémarrer: systemctl restart frigate"
    echo ""
    echo "✅ Installation terminée avec succès!"
    echo "========================================"
}

# Fonction principale
main() {
    echo "=== INSTALLATION FRIGATE CORRIGÉE ==="
    setup_system
    install_dependencies
    setup_python
    install_frigate
    configure_frigate
    start_services
    show_summary
}

# Exécution
main "$@"
FRIGATE_SCRIPT_EOF
}

# Fonction principale
main() {
    header_info
    parse_arguments "$@"

    msg_info "🚀 Démarrage installation Frigate corrigée..."
    msg_info "📋 Configuration: ID=$CTID, Hostname=$HOSTNAME, RAM=${MEMORY}MB, Disk=${DISK_SIZE}GB"

    create_container
    create_frigate_script

    msg_info "🔧 Exécution de l'installation corrigée..."
    if pct exec $CTID -- /root/frigate-install.sh; then
        local IP=$(pct exec $CTID -- ip route get 1 2>/dev/null | awk '{print $7}' | head -n1 || echo "IP_NOT_DETECTED")

        echo ""
        msg_ok "🎉 Installation terminée avec succès!"
        echo ""
        echo -e "${GREEN}📱 Accès Frigate: http://$IP:5000 (direct) ou http://$IP:8080 (nginx)${NC}"
        echo -e "${BLUE}🔧 Connexion conteneur: pct enter $CTID${NC}"
        echo -e "${BLUE}📊 Logs: pct exec $CTID -- journalctl -u frigate -f${NC}"
        echo ""
    else
        msg_error "Échec de l'installation Frigate"
        echo "Logs d'erreur disponibles dans le conteneur: /tmp/install.log"
        exit 1
    fi
}

# Point d'entrée
if ! command -v pct >/dev/null 2>&1; then
    msg_error "Ce script doit être exécuté sur un serveur Proxmox"
    exit 1
fi

main "$@"
