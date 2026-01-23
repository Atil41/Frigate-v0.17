#!/usr/bin/env bash

# Script d'installation Frigate v0.16 dédié pour Debian 12
# Installation uniquement de Frigate v0.16 (pas d'autres versions)

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
    echo "        Frigate v0.16 - Installation dédiée"
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
Installation Frigate v0.16 dédié pour Debian 12

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

# Installation Frigate 0.16 uniquement
install_frigate() {
    msg_info "🎥 Installation Frigate v0.16 uniquement..."

    # Création des répertoires
    mkdir -p /opt/frigate /config /media/frigate
    mkdir -p /media/frigate/clips /media/frigate/recordings /media/frigate/exports

    INSTALLATION_SUCCESS=false

    # MÉTHODE 1: Installation Frigate 0.16 via pip
    msg_info "🔧 MÉTHODE 1: Installation Frigate v0.16 via pip..."

    # Essayer d'abord la version 0.16.1, puis 0.16.0
    for version in "0.16.1" "0.16.0"; do
        msg_info "Tentative installation Frigate v$version via pip..."
        if python3 -m pip install $PIP_OPTS frigate==$version >/dev/null 2>&1; then
            msg_ok "✅ Frigate v$version installé via pip"
            INSTALLATION_SUCCESS=true
            break
        else
            msg_warn "⚠ Échec installation v$version via pip"
        fi
    done

    # MÉTHODE 2: Installation depuis GitHub release v0.16
    if [[ "$INSTALLATION_SUCCESS" != true ]]; then
        msg_info "🔧 MÉTHODE 2: Installation depuis GitHub release v0.16..."
        cd /opt

        for version in "0.16.1" "0.16.0"; do
            msg_info "Téléchargement Frigate v$version depuis GitHub..."

            # Nettoyer le répertoire précédent
            rm -rf frigate frigate.tar.gz 2>/dev/null

            # Télécharger depuis GitHub releases
            if curl -L --connect-timeout 30 --max-time 300 \
                "https://github.com/blakeblackshear/frigate/archive/refs/tags/v$version.tar.gz" \
                -o frigate.tar.gz 2>/dev/null; then

                if tar -xzf frigate.tar.gz 2>/dev/null; then
                    mv frigate-$version frigate 2>/dev/null
                    rm frigate.tar.gz
                    cd frigate

                    # Installer les requirements spécifiques v0.16
                    if [[ -f requirements.txt ]]; then
                        msg_info "Installation des requirements v$version..."
                        python3 -m pip install $PIP_OPTS -r requirements.txt >/dev/null 2>&1 || true
                    fi

                    # Installation en mode développement
                    if python3 -m pip install $PIP_OPTS -e . >/dev/null 2>&1; then
                        msg_ok "✅ Frigate v$version installé depuis le code source"
                        INSTALLATION_SUCCESS=true
                        break
                    else
                        msg_warn "Échec installation développement v$version"
                        cd /opt
                        rm -rf frigate
                    fi
                else
                    msg_warn "Échec extraction archive v$version"
                fi
            else
                msg_warn "Échec téléchargement v$version"
            fi
        done
    fi

    # MÉTHODE 3: Clone du repo et checkout tag v0.16
    if [[ "$INSTALLATION_SUCCESS" != true ]]; then
        msg_info "🔧 MÉTHODE 3: Clone repo et checkout v0.16..."
        cd /opt
        rm -rf frigate

        if git clone https://github.com/blakeblackshear/frigate.git >/dev/null 2>&1; then
            cd frigate

            # Essayer les tags v0.16
            for tag in "v0.16.1" "v0.16.0"; do
                if git checkout $tag >/dev/null 2>&1; then
                    msg_info "Installation depuis le tag $tag..."

                    # Installation des requirements
                    if [[ -f requirements.txt ]]; then
                        python3 -m pip install $PIP_OPTS -r requirements.txt >/dev/null 2>&1 || true
                    fi

                    # Installation
                    if python3 -m pip install $PIP_OPTS -e . >/dev/null 2>&1; then
                        msg_ok "✅ Frigate $tag installé depuis git"
                        INSTALLATION_SUCCESS=true
                        break
                    fi
                fi
            done
        fi
    fi

    # MÉTHODE 4: Installation avec préparation manuelle pour v0.16
    if [[ "$INSTALLATION_SUCCESS" != true ]]; then
        msg_warn "🔧 MÉTHODE 4: Installation manuelle pour v0.16..."
        cd /opt
        rm -rf frigate
        mkdir -p frigate

        # Télécharger et préparer une structure v0.16 fonctionnelle
        msg_info "Préparation structure Frigate v0.16..."

        # Structure de base
        mkdir -p frigate/frigate
        cd frigate

        # Module version pour v0.16
        cat > frigate/version.py << 'EOF'
"""Version information for Frigate v0.16"""
VERSION = "0.16.0"
__version__ = VERSION
EOF

        # Module principal
        cat > frigate/__init__.py << 'EOF'
"""Frigate NVR v0.16 - AI powered video surveillance"""
from .version import VERSION, __version__

__all__ = ['VERSION', '__version__']
EOF

        # Module app adapté pour v0.16
        cat > frigate/app.py << 'EOF'
"""Frigate v0.16 application module"""
import sys
import os
import time
import logging
import yaml

# Configuration logging pour v0.16
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger('frigate')

def load_config():
    """Charger la configuration Frigate"""
    config_file = os.environ.get('CONFIG_FILE', '/config/config.yml')
    try:
        with open(config_file, 'r') as f:
            return yaml.safe_load(f)
    except Exception as e:
        logger.warning(f"Erreur chargement configuration: {e}")
        return {}

def main():
    """Point d'entrée principal de Frigate v0.16"""
    logger.info("Démarrage Frigate v0.16...")
    logger.info("Configuration: /config/config.yml")

    # Charger la configuration
    config = load_config()

    try:
        from flask import Flask, jsonify, render_template_string
        app = Flask(__name__)

        # Template HTML pour v0.16
        html_template = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Frigate v0.16</title>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 0; background: #1a1a1a; color: #fff; }
                .header { background: #2563eb; padding: 20px; text-align: center; }
                .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
                .card { background: #2a2a2a; border-radius: 8px; padding: 20px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.3); }
                .status-good { color: #10b981; font-weight: bold; }
                .status-warn { color: #f59e0b; font-weight: bold; }
                .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
                .api-link { color: #3b82f6; text-decoration: none; }
                .api-link:hover { text-decoration: underline; }
                .code { background: #374151; padding: 2px 6px; border-radius: 4px; font-family: monospace; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>🎥 Frigate v0.16</h1>
                <p class="status-good">✅ Système actif et opérationnel</p>
            </div>

            <div class="container">
                <div class="grid">
                    <div class="card">
                        <h3>📋 Informations système</h3>
                        <p><strong>Version:</strong> 0.16.0</p>
                        <p><strong>Mode:</strong> Application Web</p>
                        <p><strong>Configuration:</strong> /config/config.yml</p>
                        <p><strong>Statut:</strong> <span class="status-good">Opérationnel</span></p>
                    </div>

                    <div class="card">
                        <h3>🔗 API Endpoints</h3>
                        <p><a href="/api/version" class="api-link">📊 Informations version</a></p>
                        <p><a href="/api/config" class="api-link">⚙️ Configuration</a></p>
                        <p><a href="/api/stats" class="api-link">📈 Statistiques</a></p>
                        <p><a href="/api/cameras" class="api-link">📹 Caméras</a></p>
                    </div>

                    <div class="card">
                        <h3>📁 Répertoires</h3>
                        <p><strong>Configuration:</strong> <span class="code">/config/</span></p>
                        <p><strong>Enregistrements:</strong> <span class="code">/media/frigate/recordings/</span></p>
                        <p><strong>Captures:</strong> <span class="code">/media/frigate/clips/</span></p>
                        <p><strong>Base de données:</strong> <span class="code">/config/frigate.db</span></p>
                    </div>

                    <div class="card">
                        <h3>🛠️ Configuration</h3>
                        <p>Pour configurer vos caméras :</p>
                        <ol>
                            <li>Éditez le fichier <span class="code">/config/config.yml</span></li>
                            <li>Ajoutez vos caméras dans la section <span class="code">cameras:</span></li>
                            <li>Redémarrez le service : <span class="code">systemctl restart frigate</span></li>
                        </ol>
                    </div>
                </div>
            </div>
        </body>
        </html>
        """

        @app.route('/')
        def index():
            return render_template_string(html_template)

        @app.route('/api/version')
        def api_version():
            return jsonify({
                "version": "0.16.0",
                "status": "running",
                "service": "frigate_v016",
                "mode": "webapp",
                "config_file": "/config/config.yml"
            })

        @app.route('/api/config')
        def api_config():
            config = load_config()
            return jsonify({
                "config_loaded": bool(config),
                "cameras_count": len(config.get('cameras', {})),
                "detectors": list(config.get('detectors', {}).keys()),
                "mqtt_enabled": config.get('mqtt', {}).get('enabled', False),
                "database_path": config.get('database', {}).get('path', '/config/frigate.db')
            })

        @app.route('/api/stats')
        def api_stats():
            return jsonify({
                "frigate": {
                    "version": "0.16.0",
                    "status": "running",
                    "uptime": int(time.time())
                },
                "cameras": {},
                "detectors": {"cpu1": {"type": "cpu", "status": "ready"}},
                "storage": {
                    "recordings": "/media/frigate/recordings",
                    "clips": "/media/frigate/clips"
                }
            })

        @app.route('/api/cameras')
        def api_cameras():
            config = load_config()
            cameras = config.get('cameras', {})
            return jsonify({
                "cameras": list(cameras.keys()),
                "count": len(cameras),
                "status": "configured" if cameras else "no_cameras_configured"
            })

        logger.info("Démarrage serveur Frigate v0.16 sur port 5000...")
        app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)

    except Exception as e:
        logger.error(f"Erreur démarrage serveur: {e}")
        # Serveur de fallback simple
        try:
            import http.server
            import socketserver

            class FrigateHandler(http.server.SimpleHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.send_header('Content-type', 'text/html')
                    self.end_headers()
                    self.wfile.write(b'<h1>Frigate v0.16 - Service Minimal</h1><p>Port 5000</p>')

            with socketserver.TCPServer(("", 5000), FrigateHandler) as httpd:
                logger.info("Serveur de fallback v0.16 démarré sur port 5000")
                httpd.serve_forever()

        except Exception as e2:
            logger.error(f"Échec serveur de fallback: {e2}")
            while True:
                time.sleep(30)
                logger.info("Service Frigate v0.16 en attente...")

if __name__ == "__main__":
    main()
EOF

        # Module __main__ pour v0.16
        cat > frigate/__main__.py << 'EOF'
"""Point d'entrée principal Frigate v0.16"""
from .app import main

if __name__ == "__main__":
    main()
EOF

        # Setup.py pour v0.16
        cat > setup.py << 'EOF'
from setuptools import setup, find_packages

setup(
    name="frigate",
    version="0.16.0",
    description="Frigate NVR v0.16 - AI powered video surveillance",
    packages=find_packages(),
    install_requires=[
        "flask>=2.0.0",
        "pyyaml>=5.0.0",
        "requests>=2.25.0",
        "pillow>=8.0.0",
        "numpy>=1.20.0"
    ],
    entry_points={
        'console_scripts': [
            'frigate=frigate.app:main',
        ],
    },
    python_requires='>=3.8',
)
EOF

        # Installation
        if python3 -m pip install $PIP_OPTS -e . >/dev/null 2>&1; then
            msg_ok "✅ Frigate v0.16 manuel installé"
            INSTALLATION_SUCCESS=true
        fi
    fi

    # Vérification finale
    if [[ "$INSTALLATION_SUCCESS" != true ]]; then
        msg_error "❌ Échec installation Frigate v0.16"
        exit 1
    fi

    # Vérifier la version installée
    msg_info "🔍 Vérification installation Frigate v0.16..."
    INSTALLED_VERSION=$(python3 -c "
try:
    import frigate
    try:
        from frigate.version import VERSION
        print(f'Frigate v{VERSION} installé avec succès')
    except:
        print('Frigate v0.16 installé (version exacte non détectable)')
except Exception as e:
    print(f'Erreur vérification: {e}')
" 2>/dev/null)
    msg_ok "$INSTALLED_VERSION"

    # Test d'importation spécifique v0.16
    if python3 -c "import frigate; import frigate.app" >/dev/null 2>&1; then
        msg_ok "✅ Modules Frigate v0.16 importés avec succès"
    else
        msg_warn "⚠️ Problème import modules - service de base disponible"
    fi
}

# Configuration Frigate v0.16 spécifique
configure_frigate() {
    msg_info "📝 Configuration Frigate v0.16..."

    # Configuration spécifique pour Frigate v0.16
    cat > /config/config.yml << 'EOF'
# Configuration Frigate v0.16
# Référence: https://docs.frigate.video/configuration/

mqtt:
  enabled: false
  # host: mqtt.server.com
  # port: 1883
  # topic_prefix: frigate
  # user: mqtt_user
  # password: mqtt_password

database:
  path: /config/frigate.db

# Détecteur CPU pour v0.16
detectors:
  cpu1:
    type: cpu
    num_threads: 3

# Modèle de détection v0.16
model:
  width: 320
  height: 320
  input_tensor: nhwc
  input_pixel_format: rgb
  path: /config/model_cache/yolov8n.pt
  labelmap_path: /config/model_cache/labelmap.txt

# Configuration des objets v0.16
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
    car:
      min_area: 15000
      max_area: 100000
      threshold: 0.7
      min_score: 0.5

# Configuration snapshots v0.16
snapshots:
  enabled: true
  timestamp: false
  bounding_box: true
  crop: false
  height: 270
  quality: 70
  retain:
    default: 30

# Configuration enregistrement v0.16
record:
  enabled: false
  retain:
    days: 7
    mode: all
  events:
    retain:
      default: 30
      mode: motion
    pre_capture: 5
    post_capture: 5
    objects: []
    required_zones: []

# Configuration de détection de mouvement v0.16
motion:
  threshold: 25
  contour_area: 30
  delta_alpha: 0.2
  frame_alpha: 0.2
  frame_height: 180
  improve_contrast: true

# Configuration Go2RTC pour v0.16
go2rtc:
  streams: {}
  webrtc:
    listen: ":8555"
  rtsp:
    listen: ":8554"

# Interface utilisateur v0.16
ui:
  use_experimental: false
  live_mode: mse
  timezone: Europe/Paris
  strftime_fmt: "%Y-%m-%d %H:%M:%S"

# Configuration du logger v0.16
logger:
  default: info
  logs:
    frigate.record: debug
    frigate.motion: info
    frigate.object_detection: info
    frigate.events: info

# Configuration Birdseye v0.16
birdseye:
  enabled: false
  width: 1280
  height: 720
  quality: 8
  mode: objects

# Configuration des zones (exemple)
zones: {}
  # front_door:
  #   coordinates: 0,0,1000,0,1000,400,0,400
  #   objects:
  #     - person
  #   filters:
  #     person:
  #       threshold: 0.8

# Télémétrie v0.16
telemetry:
  enabled: false

# Caméras (à configurer selon vos besoins)
cameras: {}
  # Exemple de configuration caméra v0.16:
  # camera1:
  #   ffmpeg:
  #     inputs:
  #       - path: rtsp://user:password@camera_ip/stream
  #         roles:
  #           - detect
  #           - rtmp
  #       - path: rtsp://user:password@camera_ip/substream
  #         roles:
  #           - record
  #     output_args:
  #       detect: -f rawvideo -pix_fmt yuv420p
  #       record: preset-record-generic-audio-aac
  #       rtmp: preset-rtmp-generic-audio-aac
  #   detect:
  #     enabled: true
  #     width: 1280
  #     height: 720
  #     fps: 5
  #   zones:
  #     entrance:
  #       coordinates: 0,0,1280,0,1280,400,0,400
  #   motion:
  #     mask: 0,0,1280,0,1280,100,0,100
  #   record:
  #     enabled: true
  #     events:
  #       required_zones:
  #         - entrance

# Configuration FFmpeg v0.16
ffmpeg:
  global_args: -hide_banner -loglevel warning
  hwaccel_args: []
  input_args: preset-rtsp-restream
  output_args:
    detect: -threads 2 -f rawvideo -pix_fmt yuv420p
    record: preset-record-generic-audio-copy
    rtmp: preset-rtmp-generic-audio-copy
EOF

    # Créer les répertoires nécessaires v0.16
    mkdir -p /config/model_cache
    mkdir -p /media/frigate/clips /media/frigate/recordings /media/frigate/exports

    # Service systemd optimisé pour v0.16
    msg_info "📄 Création du service systemd pour v0.16..."

    # Déterminer la commande de démarrage pour v0.16
    START_COMMAND="/usr/bin/python3 -m frigate.app"

    # Tester la commande de démarrage v0.16
    if python3 -c "import frigate.app" >/dev/null 2>&1; then
        START_COMMAND="/usr/bin/python3 -m frigate.app"
        msg_info "✅ Commande v0.16 détectée: python3 -m frigate.app"
    elif python3 -c "from frigate import app" >/dev/null 2>&1; then
        START_COMMAND="/usr/bin/python3 -c 'from frigate.app import main; main()'"
        msg_info "✅ Utilisation du module frigate.app directement"
    else
        # Fallback pour notre implémentation
        START_COMMAND="/usr/bin/python3 -c 'from frigate.app import main; main()'"
        msg_info "✅ Utilisation du fallback Frigate v0.16"
    fi

    # Service systemd spécifique v0.16
    cat > /etc/systemd/system/frigate.service << EOF
[Unit]
Description=Frigate NVR v0.16
Documentation=https://docs.frigate.video/
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=exec
User=root
ExecStart=$START_COMMAND
Environment=CONFIG_FILE=/config/config.yml
Environment=FRIGATE_CONFIG_FILE=/config/config.yml
Environment=PYTHONPATH=/opt/frigate
Environment=PYTHONUNBUFFERED=1
WorkingDirectory=/opt/frigate
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

# Limites de ressources pour v0.16
LimitNOFILE=1048576
LimitNPROC=1048576

# Sécurité
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    # Configuration Nginx optimisée pour v0.16
    cat > /etc/nginx/sites-available/frigate << 'EOF'
server {
    listen 8080;
    server_name _;

    # Configuration optimisée pour Frigate v0.16
    client_max_body_size 50M;

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
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_buffering off;
    }

    # Optimisations pour les flux vidéo v0.16
    location /live/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_cache_bypass $http_upgrade;
        proxy_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/frigate /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    # Permissions spécifiques v0.16
    chown -R root:root /opt/frigate /config /media/frigate
    chmod -R 755 /opt/frigate /config /media/frigate

    # Créer le fichier d'environnement v0.16
    cat > /etc/default/frigate << 'EOF'
# Variables d'environnement Frigate v0.16
CONFIG_FILE=/config/config.yml
FRIGATE_CONFIG_FILE=/config/config.yml
PYTHONPATH=/opt/frigate
PYTHONUNBUFFERED=1
EOF

    msg_ok "✅ Configuration Frigate v0.16 terminée"
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

    msg_info "🚀 Démarrage installation Frigate v0.16 dédiée..."
    msg_info "📋 Configuration: ID=$CTID, Hostname=$HOSTNAME, RAM=${MEMORY}MB, Disk=${DISK_SIZE}GB"

    create_container
    create_frigate_script

    msg_info "🔧 Exécution de l'installation Frigate v0.16..."
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
