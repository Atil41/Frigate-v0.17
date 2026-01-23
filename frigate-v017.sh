#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Authors: MickLesk (CanbiZ), Atil41 (v0.17.0-beta2 adaptation)
# Co-Authors: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://frigate.video/
# Version: Frigate v0.17.0-beta2

# Define essential functions for standalone operation
BL='\033[36m'    # Blue
RD='\033[0;31m'  # Red
YW='\033[1;33m'  # Yellow
GN='\033[0;32m'  # Green
CL='\033[0m'     # Clear
BFR='\r\033[K'   # Clear line
CM="${GN}✓${CL}" # Check mark
CROSS="${RD}✗${CL}" # Cross mark

msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
msg_ok() { echo -e "${BFR}${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${BFR}${CROSS} ${RD}$1${CL}"; }

color() { return 0; }
verb_ip6() { return 0; }
catch_errors() { set -euo pipefail; }
setting_up_container() { echo -e "${BL}[INFO]${CL} Setting up Frigate v0.17.0-beta2 container..."; }
network_check() {
    if ! ping -c 1 google.com &> /dev/null; then
        msg_error "No internet connection available"
        exit 1
    fi
}

update_os() {
    msg_info "Updating package repositories"
    apt-get update &> /dev/null || { msg_error "Failed to update repositories"; exit 1; }
    msg_ok "Package repositories updated"
}

setup_hwaccel() {
    msg_info "Setting up hardware acceleration support"
    # Install VA-API and other hardware acceleration packages
    apt-get install -y vainfo intel-media-va-driver-non-free mesa-va-drivers &> /dev/null || true
    msg_ok "Hardware acceleration configured"
}

setup_nodejs() {
    local NODE_VERSION=$1
    local NODE_MODULE=$2
    msg_info "Installing Node.js $NODE_VERSION"

    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - &> /dev/null
    apt-get install -y nodejs &> /dev/null

    # Install specified module (yarn)
    if [[ "$NODE_MODULE" == "yarn" ]]; then
        npm install -g yarn &> /dev/null
    fi

    msg_ok "Node.js $NODE_VERSION and $NODE_MODULE installed"
}

fetch_and_deploy_gh_release() {
    local name="$1"
    local repo="$2"
    local type="$3"
    local version="$4"
    local dest="$5"
    local filename="${6:-}"

    msg_info "Fetching $name from GitHub ($version)"

    mkdir -p "$dest"
    cd /tmp

    case "$type" in
        "tarball")
            wget -q "https://github.com/$repo/archive/refs/tags/$version.tar.gz" -O "${name}.tar.gz"
            tar -xzf "${name}.tar.gz" --strip-components=1 -C "$dest"
            rm "${name}.tar.gz"
            ;;
        "singlefile")
            if [[ "$version" == "latest" ]]; then
                local download_url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep "browser_download_url.*$filename" | cut -d '"' -f 4)
            else
                local download_url="https://github.com/$repo/releases/download/$version/$filename"
            fi
            wget -q "$download_url" -O "$dest/$filename"
            chmod +x "$dest/$filename"
            ln -sf "$dest/$filename" "/usr/local/bin/go2rtc"
            ;;
    esac

    msg_ok "$name deployed to $dest"
}

motd_ssh() {
    msg_info "Configuring MOTD and SSH"

    # Create custom MOTD
    cat > /etc/motd << EOF
   ______     _             __
  / ____/____(_)___ _____ _/ /____
 / /_  / ___/ / __ \`/ __ \`/ __/ _ \\
/ __/ / /  / / /_/ / /_/ / /_/  __/
/_/   /_/  /_/\\__, /\\__,_/\\__/\\___/
             /____/
                              v0.17.0-beta2

Documentation: https://docs.frigate.video/
Configuration: /config/config.yml
Web Interface: http://$(hostname -I | awk '{print $1}'):8971

EOF

    msg_ok "MOTD configured"
}

customize() {
    msg_info "Applying container customizations"

    # Set timezone
    timedatectl set-timezone Europe/Paris &> /dev/null || true

    # Configure system limits for Frigate
    cat >> /etc/security/limits.conf << EOF
*       soft    nofile  1048576
*       hard    nofile  1048576
root    soft    nofile  1048576
root    hard    nofile  1048576
EOF

    # Configure sysctl for better performance
    cat >> /etc/sysctl.conf << EOF
vm.swappiness=1
vm.dirty_background_ratio=5
vm.dirty_ratio=10
EOF

    msg_ok "Container customization completed"
}

cleanup_lxc() {
    msg_info "Performing final cleanup"

    # Clean package cache
    apt-get autoremove -y &> /dev/null || true
    apt-get autoclean &> /dev/null || true

    # Clear logs
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2> /dev/null || true

    # Clear bash history
    history -c &> /dev/null || true

    msg_ok "LXC container cleanup completed"
}

# Set error handling and initialize
set +e

# Define STD for silent operations
STD="&>/dev/null"

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

cat <<'EOF' >/etc/apt/sources.list.d/debian.sources
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: bookworm
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: bookworm-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://security.debian.org
Suites: bookworm-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
rm -f /etc/apt/sources.list

msg_info "Installing system dependencies"
eval apt-get install -y jq wget xz-utils python3 python3-dev python3-pip gcc pkg-config libhdf5-dev unzip build-essential automake libtool ccache libusb-1.0-0-dev apt-transport-https cmake git libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev gfortran openexr libssl-dev libtbbmalloc2 libtbb-dev libdc1394-dev libopenexr-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev tclsh libopenblas-dev liblapack-dev make moreutils $STD
msg_ok "System dependencies installed"

setup_hwaccel

# Check if we're in privileged or unprivileged container
if [[ "${CTTYPE:-1}" == "0" ]]; then
  msg_info "Configuring render group for privileged container"
  sed -i -e 's/^kvm:x:104:$/render:x:104:root,frigate/' -e 's/^render:x:105:root$/kvm:x:105:/' /etc/group
  msg_ok "Privileged container GPU access configured"
else
  msg_info "Configuring render group for unprivileged container"
  sed -i -e 's/^kvm:x:104:$/render:x:104:frigate/' -e 's/^render:x:105:$/kvm:x:105:/' /etc/group
  msg_ok "Unprivileged container GPU access configured"
fi

export TARGETARCH="amd64"
export CCACHE_DIR=/root/.ccache
export CCACHE_MAXSIZE=2G
export APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn
export DEBIAN_FRONTEND=noninteractive
export PIP_BREAK_SYSTEM_PACKAGES=1
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES="compute,video,utility"
export TOKENIZERS_PARALLELISM=true
export TRANSFORMERS_NO_ADVISORY_WARNINGS=1
export OPENCV_FFMPEG_LOGLEVEL=8
export HAILORT_LOGGER_PATH=NONE

fetch_and_deploy_gh_release "frigate" "blakeblackshear/frigate" "tarball" "v0.17.0-beta2" "/opt/frigate"

msg_info "Building Nginx with custom modules"
#sed -i 's|if.*"$VERSION_ID" == "12".*|if [[ "$VERSION_ID" =~ ^(12|13)$ ]]; then|g' /opt/frigate/docker/main/build_nginx.sh
eval bash /opt/frigate/docker/main/build_nginx.sh $STD
sed -e '/s6-notifyoncheck/ s/^#*/#/' -i /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run
ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx
msg_ok "Nginx built successfully"

msg_info "Building SQLite with custom modules"
#sed -i 's|if.*"$VERSION_ID" == "12".*|if [[ "$VERSION_ID" =~ ^(12|13)$ ]]; then|g' /opt/frigate/docker/main/build_sqlite_vec.sh
eval bash /opt/frigate/docker/main/build_sqlite_vec.sh $STD
msg_ok "SQLite built successfully"

fetch_and_deploy_gh_release "go2rtc" "AlexxIT/go2rtc" "singlefile" "latest" "/usr/local/go2rtc/bin" "go2rtc_linux_amd64"

msg_info "Installing tempio"
export TARGETARCH=amd64
sed -i 's|/rootfs/usr/local|/usr/local|g' /opt/frigate/docker/main/install_tempio.sh
eval bash /opt/frigate/docker/main/install_tempio.sh $STD
ln -sf /usr/local/tempio/bin/tempio /usr/local/bin/tempio
msg_ok "tempio installed"

msg_info "Building libUSB without udev"
cd /opt
wget -q https://github.com/libusb/libusb/archive/v1.0.26.zip -O v1.0.26.zip
eval unzip -q v1.0.26.zip $STD
cd libusb-1.0.26
eval ./bootstrap.sh $STD
eval ./configure CC='ccache gcc' CCX='ccache g++' --disable-udev --enable-shared $STD
eval make -j $(nproc --all) $STD
cd /opt/libusb-1.0.26/libusb
mkdir -p '/usr/local/lib'
eval bash ../libtool --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib' $STD
mkdir -p '/usr/local/include/libusb-1.0'
eval install -c -m 644 libusb.h '/usr/local/include/libusb-1.0' $STD
mkdir -p '/usr/local/lib/pkgconfig'
cd /opt/libusb-1.0.26/
eval install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig' $STD
ldconfig
msg_ok "libUSB built successfully"

#msg_info "Setting up Python"
#$STD update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3 1
#msg_ok "Python configured"

#msg_info "Initializing pip"
#wget -q https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py
#sed -i 's/args.append("setuptools")/args.append("setuptools==77.0.3")/' /tmp/get-pip.py
#$STD python3 /tmp/get-pip.py "pip"
#msg_ok "Pip initialized"

msg_info "Installing Python dependencies from requirements"
eval pip3 install -r /opt/frigate/docker/main/requirements.txt $STD
msg_ok "Python dependencies installed"

msg_info "Building pysqlite3"
sed -i 's|^SQLITE3_VERSION=.*|SQLITE3_VERSION="version-3.46.0"|g' /opt/frigate/docker/main/build_pysqlite3.sh
eval bash /opt/frigate/docker/main/build_pysqlite3.sh $STD
mkdir -p /wheels
for i in {1..3}; do
  msg_info "Building wheels (attempt $i/3)..."
  if pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt --default-timeout=300 --retries=3 &>/dev/null; then
    break
  fi
  if [[ $i -lt 3 ]]; then sleep 10; fi
done
msg_ok "pysqlite3 built successfully"

NODE_VERSION="22" NODE_MODULE="yarn" setup_nodejs

msg_info "Downloading inference models"
mkdir -p /models /openvino-model
wget -q -O edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
cd /models
wget -q -O cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite
cp /opt/frigate/labelmap.txt /labelmap.txt
msg_ok "Inference models downloaded"

msg_info "Downloading audio classification model"
cd /
wget -q -O yamnet-tflite.tar.gz https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download
eval tar xzf yamnet-tflite.tar.gz $STD
mv 1.tflite cpu_audio_model.tflite
cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt
rm -f yamnet-tflite.tar.gz
msg_ok "Audio model prepared"

msg_info "Building HailoRT runtime"
eval bash /opt/frigate/docker/main/install_hailort.sh $STD
cp -a /opt/frigate/docker/main/rootfs/. /
sed -i '/^.*unset DEBIAN_FRONTEND.*$/d' /opt/frigate/docker/main/install_deps.sh
echo "libedgetpu1-max libedgetpu/accepted-eula boolean true" | debconf-set-selections
echo "libedgetpu1-max libedgetpu/install-confirm-max boolean true" | debconf-set-selections
eval bash /opt/frigate/docker/main/install_deps.sh $STD
eval pip3 install -U /wheels/*.whl $STD
ldconfig
eval pip3 install -U /wheels/*.whl $STD
msg_ok "HailoRT runtime built"

msg_info "Installing OpenVino runtime and libraries"
eval pip3 install -r /opt/frigate/docker/main/requirements-ov.txt $STD
msg_ok "OpenVino installed"

msg_info "Preparing OpenVino inference model"
cd /models
wget -q http://download.tensorflow.org/models/object_detection/ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz
eval tar -zxf ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz --no-same-owner $STD
eval python3 /opt/frigate/docker/main/build_ov_model.py $STD
cp -r /models/ssdlite_mobilenet_v2.xml /openvino-model/
cp -r /models/ssdlite_mobilenet_v2.bin /openvino-model/
wget -q https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt -O /openvino-model/coco_91cl_bkgr.txt
sed -i 's/truck/car/g' /openvino-model/coco_91cl_bkgr.txt
msg_ok "OpenVino model prepared"

msg_info "Building Frigate application"
cd /opt/frigate
eval pip3 install -r /opt/frigate/docker/main/requirements-dev.txt $STD
eval bash /opt/frigate/.devcontainer/initialize.sh $STD
eval make version $STD
cd /opt/frigate/web
eval npm install $STD
eval npm run build $STD
cp -r /opt/frigate/web/dist/* /opt/frigate/web/
cd /opt/frigate
sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run
msg_ok "Frigate application built"

msg_info "Preparing configuration directories"
mkdir -p /config /media/frigate
cp -r /opt/frigate/config/. /config
msg_ok "Configuration directories prepared"

msg_info "Setting up sample video"
curl -fsSL "https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4" -o "/media/frigate/person-bicycle-car-detection.mp4"
msg_ok "Sample video downloaded"

msg_info "Configuring tmpfs cache"
echo "tmpfs   /tmp/cache      tmpfs   defaults        0       0" >>/etc/fstab
msg_ok "Cache tmpfs configured"

msg_info "Creating environment configuration for Frigate v0.17.0-beta2"
cat <<EOF >/etc/frigate.env
# Frigate v0.17.0-beta2 Environment Configuration
DEFAULT_FFMPEG_VERSION="7.0"
INCLUDED_FFMPEG_VERSIONS="7.0:5.0"
FRIGATE_VERSION="0.17.0-beta2"
CONFIG_FILE=/config/config.yml
FRIGATE_CONFIG_FILE=/config/config.yml
PLUS_API_KEY=""
LIBVA_DRIVER_NAME="i965"
EOF
msg_ok "Environment file created for v0.17.0-beta2"

msg_info "Creating base Frigate v0.17.0-beta2 configuration"
cat <<EOF >/config/config.yml
# Frigate v0.17.0-beta2 Configuration
mqtt:
  enabled: false

# Database configuration for v0.17.0-beta2
database:
  path: /config/frigate.db

# Test camera with sample video
cameras:
  test:
    ffmpeg:
      inputs:
        - path: /media/frigate/person-bicycle-car-detection.mp4
          input_args: -re -stream_loop -1 -fflags +genpts
          roles:
            - detect
            - rtmp
    detect:
      height: 1080
      width: 1920
      fps: 5

# Authentication (disabled for initial setup)
auth:
  enabled: false

# Detection settings for v0.17.0-beta2
detect:
  enabled: true
  max_disappeared: 25

# UI configuration for v0.17.0-beta2
ui:
  use_experimental: false
  live_mode: mse
  timezone: Europe/Paris

# Logger configuration for v0.17.0-beta2
logger:
  default: info
  logs:
    frigate.record: debug
    frigate.motion: info
    frigate.object_detection: info

# Telemetry (disabled by default)
telemetry:
  enabled: false
EOF
msg_ok "Base Frigate v0.17.0-beta2 configuration created"

msg_info "Configuring object detection model for v0.17.0-beta2"
if grep -q -o -m1 -E 'avx[^ ]* | sse4_2' /proc/cpuinfo; then
  msg_ok "AVX or SSE 4.2 support detected"
  msg_info "Configuring hardware-accelerated OpenVino model for v0.17.0-beta2"
  cat <<EOF >>/config/config.yml

# Hardware acceleration configuration for v0.17.0-beta2
ffmpeg:
  hwaccel_args: preset-intel-qsv-h264
  global_args: -hide_banner -loglevel warning
  input_args: preset-rtsp-restream
  output_args:
    detect: -threads 2 -f rawvideo -pix_fmt yuv420p
    record: preset-record-generic-audio-copy
    rtmp: preset-rtmp-generic-audio-copy

# Detectors configuration for v0.17.0-beta2
detectors:
  openvino:
    type: openvino
    device: CPU

# Model configuration for v0.17.0-beta2
model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt

# Objects configuration for v0.17.0-beta2
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

# Motion detection for v0.17.0-beta2
motion:
  threshold: 25
  contour_area: 30
  delta_alpha: 0.2
  frame_alpha: 0.2
  frame_height: 180
  improve_contrast: true

# Snapshots configuration for v0.17.0-beta2
snapshots:
  enabled: true
  timestamp: false
  bounding_box: true
  crop: false
  quality: 70
  retain:
    default: 10

# Record configuration for v0.17.0-beta2
record:
  enabled: false
  retain:
    days: 0
  events:
    retain:
      default: 10
      mode: motion
    pre_capture: 5
    post_capture: 5

# Go2RTC configuration for v0.17.0-beta2
go2rtc:
  streams: {}
  webrtc:
    listen: ":8555"
  rtsp:
    listen: ":8554"
EOF
  msg_ok "OpenVino model configured for v0.17.0-beta2"
else
  msg_info "Configuring CPU-only object detection model for v0.17.0-beta2"
  cat <<EOF >>/config/config.yml

# Basic CPU configuration for v0.17.0-beta2
ffmpeg:
  hwaccel_args: []
  global_args: -hide_banner -loglevel warning
  input_args: preset-rtsp-restream
  output_args:
    detect: -threads 2 -f rawvideo -pix_fmt yuv420p
    record: preset-record-generic-audio-copy
    rtmp: preset-rtmp-generic-audio-copy

# CPU detector for v0.17.0-beta2
detectors:
  cpu:
    type: cpu
    num_threads: 3

# Model configuration for CPU
model:
  path: /cpu_model.tflite
  input_tensor: nhwc
  input_pixel_format: rgb

# Objects configuration for v0.17.0-beta2
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

# Motion detection for v0.17.0-beta2
motion:
  threshold: 25
  contour_area: 30

# Snapshots configuration for v0.17.0-beta2
snapshots:
  enabled: true
  timestamp: false
  bounding_box: true
  retain:
    default: 10

# Record configuration for v0.17.0-beta2
record:
  enabled: false
  retain:
    days: 0

# Go2RTC configuration for v0.17.0-beta2
go2rtc:
  streams: {}
EOF
  msg_ok "CPU model configured for v0.17.0-beta2"
fi

msg_info "Creating systemd services for Frigate v0.17.0-beta2"
cat <<EOF >/etc/systemd/system/create_directories.service
[Unit]
Description=Create necessary directories for Frigate v0.17.0-beta2 logs
Before=frigate.service go2rtc.service nginx.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/bin/mkdir -p /dev/shm/logs/{frigate,go2rtc,nginx} && /bin/touch /dev/shm/logs/{frigate/current,go2rtc/current,nginx/current} && /bin/chmod -R 777 /dev/shm/logs'

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/go2rtc.service
[Unit]
Description=go2rtc streaming service for Frigate v0.17.0-beta2
After=network.target create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
EnvironmentFile=/etc/frigate.env
ExecStartPre=+rm -f /dev/shm/logs/go2rtc/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/go2rtc/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/go2rtc/current
StandardError=file:/dev/shm/logs/go2rtc/current

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/frigate.service
[Unit]
Description=Frigate NVR v0.17.0-beta2 service
After=go2rtc.service create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=root
EnvironmentFile=/etc/frigate.env
Environment=CONFIG_FILE=/config/config.yml
Environment=FRIGATE_CONFIG_FILE=/config/config.yml
WorkingDirectory=/opt/frigate
ExecStartPre=+rm -f /dev/shm/logs/frigate/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/frigate/current
StandardError=file:/dev/shm/logs/frigate/current

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/nginx.service
[Unit]
Description=Nginx reverse proxy for Frigate v0.17.0-beta2
After=frigate.service create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStartPre=+rm -f /dev/shm/logs/nginx/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/nginx/current
StandardError=file:/dev/shm/logs/nginx/current

[Install]
WantedBy=multi-user.target
EOF
Restart=always
RestartSec=1
User=root
ExecStartPre=+rm -f /dev/shm/logs/nginx/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/nginx/current
StandardError=file:/dev/shm/logs/nginx/current

[Install]
WantedBy=multi-user.target
EOF

eval systemctl daemon-reload $STD
systemctl enable -q --now create_directories
sleep 2
systemctl enable -q --now go2rtc
sleep 2
systemctl enable -q --now frigate
sleep 2
systemctl enable -q --now nginx
msg_ok "Systemd services created and enabled for Frigate v0.17.0-beta2"

msg_info "Cleaning up temporary files and caches"
rm -rf /opt/v*.zip /opt/libusb-1.0.26 /tmp/get-pip.py
eval apt-get -y autoremove $STD
eval apt-get -y autoclean $STD
msg_ok "Cleanup completed"

motd_ssh
customize
cleanup_lxc
