#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Authors: MickLesk (CanbiZ)
# Co-Authors: remz1337
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://frigate.video/

APP="Frigate"
var_tags="nvr;ai;cctv"
var_cpu="4"
var_ram="4096"
var_disk="32"
var_os="debian"
var_version="12"
var_unprivileged="1"

# Detect if we're running inside a container or on Proxmox host
if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] || [[ -n "$CONTAINER" ]] || [[ "$1" == "--install" ]]; then
    # We're inside a container - run Frigate installation
    exec_frigate_install() {
        source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
        set +e
        color
        verb_ip6
        catch_errors
        setting_up_container
        network_check
        update_os

        # Continue with Frigate installation...

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
$STD apt-get install -y jq wget xz-utils python3 python3-dev python3-pip gcc pkg-config libhdf5-dev unzip build-essential automake libtool ccache libusb-1.0-0-dev apt-transport-https cmake git libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev gfortran openexr libssl-dev libtbbmalloc2 libtbb-dev libdc1394-dev libopenexr-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev tclsh libopenblas-dev liblapack-dev make moreutils
msg_ok "System dependencies installed"

setup_hwaccel

if [[ "$CTTYPE" == "0" ]]; then
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
$STD bash /opt/frigate/docker/main/build_nginx.sh
sed -e '/s6-notifyoncheck/ s/^#*/#/' -i /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run
ln -sf /usr/local/nginx/sbin/nginx /usr/local/bin/nginx
msg_ok "Nginx built successfully"

msg_info "Building SQLite with custom modules"
#sed -i 's|if.*"$VERSION_ID" == "12".*|if [[ "$VERSION_ID" =~ ^(12|13)$ ]]; then|g' /opt/frigate/docker/main/build_sqlite_vec.sh
$STD bash /opt/frigate/docker/main/build_sqlite_vec.sh
msg_ok "SQLite built successfully"

...existing code...

fetch_and_deploy_gh_release "go2rtc" "AlexxIT/go2rtc" "singlefile" "latest" "/usr/local/go2rtc/bin" "go2rtc_linux_amd64"

msg_info "Installing tempio"
export TARGETARCH=amd64
sed -i 's|/rootfs/usr/local|/usr/local|g' /opt/frigate/docker/main/install_tempio.sh
$STD bash /opt/frigate/docker/main/install_tempio.sh
ln -sf /usr/local/tempio/bin/tempio /usr/local/bin/tempio
msg_ok "tempio installed"

msg_info "Building libUSB without udev"
cd /opt
wget -q https://github.com/libusb/libusb/archive/v1.0.26.zip -O v1.0.26.zip
$STD unzip -q v1.0.26.zip
cd libusb-1.0.26
$STD ./bootstrap.sh
$STD ./configure CC='ccache gcc' CCX='ccache g++' --disable-udev --enable-shared
$STD make -j $(nproc --all)
cd /opt/libusb-1.0.26/libusb
mkdir -p '/usr/local/lib'
$STD bash ../libtool --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib'
mkdir -p '/usr/local/include/libusb-1.0'
$STD install -c -m 644 libusb.h '/usr/local/include/libusb-1.0'
mkdir -p '/usr/local/lib/pkgconfig'
cd /opt/libusb-1.0.26/
$STD install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig'
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
$STD pip3 install -r /opt/frigate/docker/main/requirements.txt
msg_ok "Python dependencies installed"

msg_info "Building pysqlite3"
sed -i 's|^SQLITE3_VERSION=.*|SQLITE3_VERSION="version-3.46.0"|g' /opt/frigate/docker/main/build_pysqlite3.sh
$STD bash /opt/frigate/docker/main/build_pysqlite3.sh
mkdir -p /wheels
for i in {1..3}; do
  msg_info "Building wheels (attempt $i/3)..."
  pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt --default-timeout=300 --retries=3 && break
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
$STD tar xzf yamnet-tflite.tar.gz
mv 1.tflite cpu_audio_model.tflite
cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt
rm -f yamnet-tflite.tar.gz
msg_ok "Audio model prepared"

msg_info "Building HailoRT runtime"
$STD bash /opt/frigate/docker/main/install_hailort.sh
cp -a /opt/frigate/docker/main/rootfs/. /
sed -i '/^.*unset DEBIAN_FRONTEND.*$/d' /opt/frigate/docker/main/install_deps.sh
echo "libedgetpu1-max libedgetpu/accepted-eula boolean true" | debconf-set-selections
echo "libedgetpu1-max libedgetpu/install-confirm-max boolean true" | debconf-set-selections
$STD bash /opt/frigate/docker/main/install_deps.sh
$STD pip3 install -U /wheels/*.whl
ldconfig
$STD pip3 install -U /wheels/*.whl
msg_ok "HailoRT runtime built"

msg_info "Installing OpenVino runtime and libraries"
$STD pip3 install -r /opt/frigate/docker/main/requirements-ov.txt
msg_ok "OpenVino installed"

msg_info "Preparing OpenVino inference model"
cd /models
wget -q http://download.tensorflow.org/models/object_detection/ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz
$STD tar -zxf ssdlite_mobilenet_v2_coco_2018_05_09.tar.gz --no-same-owner
$STD python3 /opt/frigate/docker/main/build_ov_model.py
cp -r /models/ssdlite_mobilenet_v2.xml /openvino-model/
cp -r /models/ssdlite_mobilenet_v2.bin /openvino-model/
wget -q https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt -O /openvino-model/coco_91cl_bkgr.txt
sed -i 's/truck/car/g' /openvino-model/coco_91cl_bkgr.txt
msg_ok "OpenVino model prepared"

msg_info "Building Frigate application"
cd /opt/frigate
$STD pip3 install -r /opt/frigate/docker/main/requirements-dev.txt
$STD bash /opt/frigate/.devcontainer/initialize.sh
$STD make version
cd /opt/frigate/web
$STD npm install
$STD npm run build
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

msg_info "Creating environment configuration"
cat <<EOF >/etc/frigate.env
DEFAULT_FFMPEG_VERSION="7.0"
INCLUDED_FFMPEG_VERSIONS="7.0:5.0"
EOF
msg_ok "Environment file created"

msg_info "Creating base Frigate configuration"
cat <<EOF >/config/config.yml
mqtt:
  enabled: false
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
auth:
  enabled: false
detect:
  enabled: false
EOF
msg_ok "Base Frigate configuration created"

msg_info "Configuring object detection model"
if grep -q -o -m1 -E 'avx[^ ]* | sse4_2' /proc/cpuinfo; then
  msg_ok "AVX or SSE 4.2 support detected"
  msg_info "Configuring hardware-accelerated OpenVino model"
  cat <<EOF >>/config/config.yml
ffmpeg:
  hwaccel_args: auto
detectors:
  detector01:
    type: openvino
model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt
EOF
  msg_ok "OpenVino model configured"
else
  msg_info "Configuring CPU-only object detection model"
  cat <<EOF >>/config/config.yml
ffmpeg:
  hwaccel_args: auto
model:
  path: /cpu_model.tflite
EOF
  msg_ok "CPU model configured"
fi

msg_info "Creating systemd services"
cat <<EOF >/etc/systemd/system/create_directories.service
[Unit]
Description=Create necessary directories for Frigate logs
Before=frigate.service go2rtc.service nginx.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/bin/mkdir -p /dev/shm/logs/{frigate,go2rtc,nginx} && /bin/touch /dev/shm/logs/{frigate/current,go2rtc/current,nginx/current} && /bin/chmod -R 777 /dev/shm/logs'

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/go2rtc.service
[Unit]
Description=go2rtc streaming service
After=network.target create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
EnvironmentFile=/etc/frigate.env
ExecStartPre=+rm /dev/shm/logs/go2rtc/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/go2rtc/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/go2rtc/current
StandardError=file:/dev/shm/logs/go2rtc/current

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/frigate.service
[Unit]
Description=Frigate NVR service
After=go2rtc.service create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
EnvironmentFile=/etc/frigate.env
ExecStartPre=+rm /dev/shm/logs/frigate/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/frigate/current
StandardError=file:/dev/shm/logs/frigate/current

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/nginx.service
[Unit]
Description=Nginx reverse proxy for Frigate
After=frigate.service create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStartPre=+rm /dev/shm/logs/nginx/current
ExecStart=/bin/bash -c "bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run 2> >(/usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S ' >&2) | /usr/bin/ts '%%Y-%%m-%%d %%H:%%M:%%.S '"
StandardOutput=file:/dev/shm/logs/nginx/current
StandardError=file:/dev/shm/logs/nginx/current

[Install]
WantedBy=multi-user.target
EOF

$STD systemctl daemon-reload
systemctl enable -q --now create_directories
sleep 2
systemctl enable -q --now go2rtc
sleep 2
systemctl enable -q --now frigate
sleep 2
systemctl enable -q --now nginx
msg_ok "Systemd services created and enabled"

msg_info "Cleaning up temporary files and caches"
rm -rf /opt/v*.zip /opt/libusb-1.0.26 /tmp/get-pip.py
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleanup completed"

motd_ssh
customize
cleanup_lxc

    }

    # Execute the installation function
    exec_frigate_install

else
    # We're on Proxmox host - create LXC container and install Frigate

    # Variables for LXC creation
    NSAPP=$(echo ${APP,,} | tr -d ' ')
    var_install="${NSAPP}-install"
    NEXTID=$(pvesh get /cluster/nextid)

    # Set colors
    YW='\033[33m'
    BL='\033[36m'
    RD='\033[01;31m'
    BGN='\033[4;92m'
    GN='\033[1;92m'
    DGN='\033[32m'
    CL='\033[0m'
    BFR='\r\033[K'
    HOLD='▇'
    CM="${GN}✓${CL}"
    CROSS="${RD}✗${CL}"

    function header_info {
        clear
        cat <<"EOF"
    ______     _             __
   / ____/____(_)___ _____ _/ /____
  / /_  / ___/ / __ `/ __ `/ __/ _ \
 / __/ / /  / / /_/ / /_/ / /_/  __/
/_/   /_/  /_/\__, /\__,_/\__/\___/
             /____/                v0.17.0-beta2

EOF
    }

    function msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
    function msg_ok() { echo -e "${BFR}${CM} ${GN}$1${CL}"; }
    function msg_error() { echo -e "${BFR}${CROSS} ${RD}$1${CL}"; }

    function default_settings() {
        CT_TYPE="$var_unprivileged"
        PW=""
        CT_ID=$NEXTID
        HN=$NSAPP
        DISK_SIZE="$var_disk"
        CORE_COUNT="$var_cpu"
        RAM_SIZE="$var_ram"
        BRG="vmbr0"
        NET="dhcp"
        GATE=""
        APT_CACHER=""
        APT_CACHER_IP=""
        DISABLEIP6="no"
        MTU=""
        SD=""
        NS=""
        MAC=""
        VLAN=""
        SSH="no"
        VERB="no"
    }

    function start() {
        if command -v pveversion >/dev/null 2>&1; then
            if ! (whiptail --title "${APP} LXC" --yesno "This will create a New ${APP} LXC. Proceed?" 10 58); then
                clear
                exit
            fi
            NEXTID=$(pvesh get /cluster/nextid)
        else
            if ! (whiptail --title "${APP} LXC" --yesno "This will create a New ${APP} LXC. Proceed?" 10 58); then
                clear
                exit
            fi
            NEXTID="$(($RANDOM * 2 / 32767 + 100))"
        fi
    }

    function build_container() {
        msg_info "Building LXC container"

        STORAGE_TYPE=$(pvesm status -storage ${STORAGE} | awk 'NR>1 {print $2}')
        case $STORAGE_TYPE in
            dir|nfs)
                DISK_EXT=".raw"
                DISK_REF="$CT_ID/"
                ;;
            zfspool)
                DISK_PREFIX="subvol"
                DISK_FORMAT="subvol"
                ;;
        esac

        DISK=${DISK_PREFIX:-vm}-${CT_ID}-disk-0${DISK_EXT:-}
        ROOTFS=${STORAGE}:${DISK_REF:-}${DISK}

        # Template path
        local template_file="debian-${var_version}-standard_${var_version}.7-1_amd64.tar.zst"

        if ! pveam list local | grep -q "$template_file"; then
            msg_info "Downloading $template_file template"
            pveam download local "$template_file"
        fi

        # Generate password if empty
        if [[ -z "$PW" ]]; then
            PW=$(openssl rand -base64 32)
        fi

        pct create $CT_ID local:vztmpl/$template_file \
            -arch $(dpkg --print-architecture) \
            -cores $CORE_COUNT \
            -hostname $HN \
            -memory $RAM_SIZE \
            -rootfs $ROOTFS,size=$DISK_SIZE \
            -tags "$var_tags" \
            -net0 name=eth0,bridge=$BRG,ip=$NET$GATE$MAC$VLAN \
            -onboot 1 \
            -protection 0 \
            -features nesting=1 \
            -unprivileged $CT_TYPE \
            $SD $NS >/dev/null

        msg_ok "LXC container $CT_ID was successfully created"
    }

    function start_container() {
        msg_info "Starting LXC container"
        pct start $CT_ID
        pct exec $CT_ID -- bash -c "
            until [[ \$(systemctl is-system-running) == *'running'* ]]; do
                sleep 1
            done
        " || true
        msg_ok "Started LXC container"
    }

    function description() {
        IP=$(pct exec $CT_ID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
        cat << EOF

${APP} should now be reachable by going to the following URL.

         ${BL}http://${IP}:8971${CL}

EOF
    }

    # Main execution for Proxmox host
    header_info
    echo "This script will create a New LXC Container with the latest version of ${APP}."
    echo "Press any key to continue..."
    read -n 1 -s
    echo ""

    # Set default storage
    STORAGE="local-lvm"

    start
    default_settings
    build_container
    start_container

    # Install Frigate inside container
    msg_info "Installing ${APP}"

    # Define FUNCTIONS_FILE_PATH for the container
    FUNCTIONS_FILE_PATH=$(cat << 'FUNC_EOF'
source /dev/stdin <<< "$(wget -qLO - https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)"
FUNC_EOF
)

    # Execute this script inside the container with --install flag
    pct exec $CT_ID -- bash -c "
        FUNCTIONS_FILE_PATH='$FUNCTIONS_FILE_PATH'
        $(cat "$0")
    " -- --install

    description
    msg_ok "${APP} setup has been successfully initialized!"

fi

