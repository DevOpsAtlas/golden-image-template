#!/bin/bash
set -e

# Constants
MIN_DEBIAN_VERSION=11
SUPPORTED_ARCHS=("amd64" "arm64")
REQUIRED_CMDS=("wget" "cpio" "gzip" "update-grub" "grub-reboot")
DEFAULT_MIRROR_HOST="deb.debian.org"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    exit 1
}

sanitize_mirror_host() {
    local input="$1"
    input=${input#http://}
    input=${input#https://}
    input=${input%%/*}
    echo "$input"
}

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root."
fi

# 2. OS Detection
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" != "debian" ]; then
        error "Host OS must be Debian. Detected: $ID"
    fi
    if [ -n "$VERSION_ID" ] && [ "$VERSION_ID" -lt "$MIN_DEBIAN_VERSION" ]; then
        error "Debian version must be $MIN_DEBIAN_VERSION or higher. Detected: $VERSION_ID"
    fi
    HOST_VERSION_ID="$VERSION_ID"
else
    error "Cannot detect OS. /etc/os-release not found."
fi

# 3. Arch Detection
ARCH=$(dpkg --print-architecture)
ARCH_SUPPORTED=false
for a in "${SUPPORTED_ARCHS[@]}"; do
    if [ "$ARCH" == "$a" ]; then
        ARCH_SUPPORTED=true
        break
    fi
done

if [ "$ARCH_SUPPORTED" = false ]; then
    error "Architecture $ARCH is not supported. Supported: ${SUPPORTED_ARCHS[*]}"
fi

# 4. Dependency Check & Install
MISSING_DEPS=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log "Missing dependencies: ${MISSING_DEPS[*]}. Installing..."
    apt-get update
    apt-get install -y "${MISSING_DEPS[@]}"
fi

# 5. Argument Parsing
IMAGE_URL=""
TARGET_DEV=""
MIRROR_HOST="$DEFAULT_MIRROR_HOST"
USE_DHCP=false
NET_IP=""
NET_MASK=""
NET_GW=""
NET_DNS=""
NET_IP6=""
NET_PREFIX6=""
NET_GW6=""
NET_DNS6=""

usage() {
    cat <<EOF
Usage: $0 --image-url <url> [options]

Required:
  --image-url <url>          HTTP(S) URL of debian-trixie-ext4.img.gz

Recommended:
  --dev <device>             Target disk (e.g. /dev/sda, /dev/nvme0n1). Defaults to current root disk.

Network (choose one):
  --dhcp                     Use DHCP. You may still pass --dns to override DNS servers.
  --ip <addr>                Static IPv4 address
  --netmask <mask>           Netmask for the static IP (e.g. 255.255.255.0)
  --gateway <gw>             Default gateway
  --dns <list>               DNS servers (space- or comma-separated). Highest priority; never overridden.
  --dns6 <list>              IPv6 DNS servers (space- or comma-separated). If omitted, auto-detect and then fallback to 2001:4860:4860::8888.

Mirror (optional):
  --mirror <host>            Mirror hostname (no scheme/path). Default: $DEFAULT_MIRROR_HOST
  --cn-mirror                Shortcut for China users; sets mirror host to mirrors.ustc.edu.cn

Notes:
  - If any static field is missing, the script will auto-detect values from the current default interface
    but will NOT overwrite values you provided.
EOF
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --image-url) IMAGE_URL="$2"; shift ;;
        --dev) TARGET_DEV="$2"; shift ;;
        --dhcp) USE_DHCP=true ;;
        --ip) NET_IP="$2"; shift ;;
        --netmask) NET_MASK="$2"; shift ;;
        --gateway) NET_GW="$2"; shift ;;
        --dns) NET_DNS="$2"; shift ;;
        --dns6) NET_DNS6="$2"; shift ;;
        --mirror) MIRROR_HOST="$2"; shift ;;
        --cn-mirror) MIRROR_HOST="mirrors.ustc.edu.cn" ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

MIRROR_HOST=$(sanitize_mirror_host "$MIRROR_HOST")

# Normalize DNS list (accept comma- or space-separated)
if [ -n "$NET_DNS" ]; then
    NET_DNS=$(echo "$NET_DNS" | tr ',' ' ' | xargs)
fi
if [ -n "$NET_DNS6" ]; then
    NET_DNS6=$(echo "$NET_DNS6" | tr ',' ' ' | xargs)
fi

if [ -z "$IMAGE_URL" ]; then
    error "--image-url is required."
fi

if [ -z "$TARGET_DEV" ]; then
    # Try to detect the root device
    TARGET_DEV=$(findmnt / -n -o SOURCE | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//')
    log "Target device not specified. Detected root device: $TARGET_DEV"
fi

if [ ! -b "$TARGET_DEV" ]; then
    error "Target device $TARGET_DEV is not a block device."
fi

# Network Auto-Detection (fill only missing fields; user-supplied values win)
if [ "$USE_DHCP" = false ]; then
    if [ -z "$NET_IP" ] || [ -z "$NET_MASK" ] || [ -z "$NET_GW" ] || [ -z "$NET_DNS" ]; then
        log "Some static network fields are missing. Auto-detecting from default interface (user-supplied values preserved)..."

        # Get default route interface
        DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

        if [ -n "$DEFAULT_IFACE" ]; then
            # Get IPv4 Info
            IP_INFO=$(ip -o -4 addr show dev "$DEFAULT_IFACE" | awk '{print $4}' | head -n1)
            IP_ADDR=${IP_INFO%/*}
            CIDR=${IP_INFO#*/}

            if [ -z "$NET_IP" ] && [ -n "$IP_ADDR" ]; then
                NET_IP=$IP_ADDR
            fi

            if [ -z "$NET_MASK" ] && [ -n "$CIDR" ]; then
                if command -v python3 &>/dev/null; then
                    NET_MASK=$(python3 -c "import ipaddress; print(str(ipaddress.IPv4Network('0.0.0.0/$CIDR').netmask))")
                else
                    case $CIDR in
                        24) NET_MASK="255.255.255.0" ;;
                        16) NET_MASK="255.255.0.0" ;;
                        8)  NET_MASK="255.0.0.0" ;;
                        *)  error "Could not calculate netmask for CIDR /$CIDR. Please install python3 or specify --netmask manually." ;;
                    esac
                fi
            fi

            if [ -z "$NET_GW" ]; then
                NET_GW=$(ip route | grep default | awk '{print $3}' | head -n1)
            fi

            if [ -z "$NET_DNS" ]; then
                NET_DNS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | head -n1)
            fi
            if [ -z "$NET_DNS6" ]; then
                NET_DNS6=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | grep ':' | head -n1)
            fi

            # Get IPv6 Info (Global only)
            IP6_INFO=$(ip -o -6 addr show dev "$DEFAULT_IFACE" scope global | awk '{print $4}' | head -n1)
            if [ -n "$IP6_INFO" ]; then
                if [ -z "$NET_IP6" ]; then NET_IP6=${IP6_INFO%/*}; fi
                if [ -z "$NET_PREFIX6" ]; then NET_PREFIX6=${IP6_INFO#*/}; fi
                if [ -z "$NET_GW6" ]; then NET_GW6=$(ip -6 route | grep default | awk '{print $3}' | head -n1); fi
            fi

            log "Auto-detected network (kept user overrides):"
            log "  Interface: $DEFAULT_IFACE"
            log "  IPv4: $NET_IP"
            log "  Netmask: $NET_MASK"
            log "  Gateway: $NET_GW"
            log "  DNS: $NET_DNS"
            if [ -n "$NET_IP6" ]; then
                log "  IPv6: $NET_IP6/$NET_PREFIX6"
                log "  Gateway6: $NET_GW6"
                log "  DNS6: $NET_DNS6"
            fi
        else
            error "Could not detect default interface. Please specify network settings manually."
        fi
    fi
fi

if [ "$USE_DHCP" = false ]; then
    if [ -z "$NET_IP" ] || [ -z "$NET_MASK" ] || [ -z "$NET_GW" ] || [ -z "$NET_DNS" ]; then
        error "Static network configuration requires --ip, --netmask, --gateway, and --dns. Or use --dhcp."
    fi

    # Ensure we have a CIDR prefix for systemd-networkd (Address= needs /XX)
    if [ -z "$CIDR" ]; then
        if command -v python3 &>/dev/null; then
            CIDR=$(python3 - <<EOF
import ipaddress
print(ipaddress.IPv4Network('0.0.0.0/${NET_MASK}').prefixlen)
EOF
)
        else
            case "$NET_MASK" in
                255.255.255.255) CIDR=32 ;;
                255.255.255.254) CIDR=31 ;;
                255.255.255.252) CIDR=30 ;;
                255.255.255.248) CIDR=29 ;;
                255.255.255.240) CIDR=28 ;;
                255.255.255.224) CIDR=27 ;;
                255.255.255.192) CIDR=26 ;;
                255.255.255.128) CIDR=25 ;;
                255.255.255.0)   CIDR=24 ;;
                255.255.254.0)   CIDR=23 ;;
                255.255.252.0)   CIDR=22 ;;
                255.255.248.0)   CIDR=21 ;;
                255.255.240.0)   CIDR=20 ;;
                255.255.224.0)   CIDR=19 ;;
                255.255.192.0)   CIDR=18 ;;
                255.255.128.0)   CIDR=17 ;;
                255.255.0.0)     CIDR=16 ;;
                255.254.0.0)     CIDR=15 ;;
                255.252.0.0)     CIDR=14 ;;
                255.248.0.0)     CIDR=13 ;;
                255.240.0.0)     CIDR=12 ;;
                255.224.0.0)     CIDR=11 ;;
                255.192.0.0)     CIDR=10 ;;
                255.128.0.0)     CIDR=9  ;;
                255.0.0.0)       CIDR=8  ;;
                *) error "Could not calculate CIDR for netmask $NET_MASK. Install python3 or use a supported mask." ;;
            esac
        fi
    fi
fi

IPV6_DNS_FALLBACK="2001:4860:4860::8888"
if [ "$USE_DHCP" = false ] && [ -n "$NET_IP6" ]; then
    if [ -z "$NET_DNS6" ]; then
        NET_DNS6=$IPV6_DNS_FALLBACK
    fi
fi

# Confirmation
echo "------------------------------------------------"
echo "Please verify the following settings:"
echo "  Target Device: $TARGET_DEV"
echo "  Image URL:     $IMAGE_URL"
echo "  Mirror Host:   $MIRROR_HOST"
if [ "$USE_DHCP" = true ]; then
    echo "  Network:       DHCP"
else
    echo "  Network:       Static"
    echo "    IPv4:    $NET_IP"
    echo "    Netmask: $NET_MASK"
    echo "    Gateway: $NET_GW"
    echo "    DNS:     $NET_DNS"
    if [ -n "$NET_IP6" ]; then
        echo "    IPv6:    $NET_IP6/$NET_PREFIX6"
        echo "    Gateway6: $NET_GW6"
        echo "    DNS6:   $NET_DNS6"
    fi
fi
echo "------------------------------------------------"
read -p "Are these settings correct? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    error "Aborted by user."
fi

log "Environment check passed."
log "  OS: Debian $HOST_VERSION_ID"
log "  Arch: $ARCH"
log "  Target Device: $TARGET_DEV"
log "  Image URL: $IMAGE_URL"
log "  Mirror Host: $MIRROR_HOST"
if [ "$USE_DHCP" = true ]; then
    log "  Network: DHCP"
else
    log "  Network: Static ($NET_IP)"
fi

# 6. Prepare Workspace
WORK_DIR="/boot/reinstall"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 7. Download Netboot Assets
if grep -q "bullseye" /etc/os-release; then
    DIST="bullseye"
elif grep -q "bookworm" /etc/os-release; then
    DIST="bookworm"
elif grep -q "trixie" /etc/os-release; then
    DIST="trixie"
else
    DIST="stable"
fi

BASE_URL="http://$MIRROR_HOST/debian/dists/$DIST/main/installer-$ARCH/current/images/netboot/debian-installer/$ARCH"

log "Downloading netboot assets from $BASE_URL..."
if [ ! -f linux ]; then
    wget -q "$BASE_URL/linux" -O linux
fi
if [ ! -f initrd.gz ]; then
    wget -q "$BASE_URL/initrd.gz" -O initrd.gz
fi

# 8. Generate Preseed
log "Generating preseed.cfg..."

cat > preseed.cfg <<EOF
# Locale, Country, and Keyboard settings
d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us
d-i time/zone string UTC

# Network configuration
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string debian
d-i netcfg/get_domain string local

# Mirror settings (to avoid prompts)
d-i mirror/country string manual
d-i mirror/http/hostname string $MIRROR_HOST
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# Account setup (dummy, to avoid prompts)
d-i passwd/make-user boolean true
d-i passwd/user-fullname string Debian User
d-i passwd/username string debian
d-i passwd/user-password string insecure
d-i passwd/user-password-again string insecure
d-i passwd/root-login boolean true
d-i passwd/root-password string insecure
d-i passwd/root-password-again string insecure
EOF

if [ "$USE_DHCP" = true ]; then
    cat >> preseed.cfg <<EOF
d-i netcfg/disable_autoconfig boolean false
d-i netcfg/dhcp_timeout string 60
d-i netcfg/dhcp_options select config
EOF
else
    cat >> preseed.cfg <<EOF
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/get_nameservers string $NET_DNS
d-i netcfg/get_ipaddress string $NET_IP
d-i netcfg/get_netmask string $NET_MASK
d-i netcfg/get_gateway string $NET_GW
d-i netcfg/confirm_static boolean true
EOF
fi

# The destructive part: Download and DD
# We use partman/early_command to run our script before partitioning starts.

# Create the install script
cat > install_image.sh <<EOF
#!/bin/sh
set -x

echo "Starting Image Installation..."
echo "Target Device: $TARGET_DEV"
echo "Image URL: $IMAGE_URL"

# 1. 预防性措施：尝试卸载目标设备上的残留挂载（静默失败）
umount -l "$TARGET_DEV"* 2>/dev/null || true
swapoff -a 2>/dev/null || true

# 2. 加载常见文件系统模块 (防止因缺模块导致 mount 失败)
modprobe ext4 2>/dev/null || true

# 3. 写入镜像
echo "Writing image from $IMAGE_URL..."
if wget -qO- "$IMAGE_URL" | gunzip -dc | /bin/dd of="$TARGET_DEV" bs=4M; then
    echo "Image written. Syncing disk..."
    sync
    sleep 3

    # 4. 强制刷新分区表
    echo "Rereading partition table..."
    blockdev --rereadpt "$TARGET_DEV" || true
    # 再次尝试触发 udev，但不依赖它
    if command -v udevadm >/dev/null; then
        udevadm trigger
        udevadm settle --timeout=10 || true
    fi
    sleep 5

    # 5. 寻找并挂载根分区 (核心修复逻辑)
    echo "Scanning for root partition..."
    ROOT_MOUNTED=false
    mkdir -p /mnt/target

    # 获取目标磁盘的内核名称 (例如 sda 或 nvme0n1)
    # 这里的 basename 处理是为了从 /dev/sda 拿到 sda
    DISK_NAME=\$(basename "$TARGET_DEV")

    # 直接读取 /proc/partitions，这是内核的真理，不依赖 /dev 文件是否存在
    # 我们查找属于该磁盘的分区 (例如 sda1, sda2...)
    # 排除磁盘本身 (sda)，只看分区
    PARTITIONS=\$(awk -v disk="\$DISK_NAME" '\$4 ~ "^"disk && \$4 != disk {print \$4}' /proc/partitions)

    if [ -z "\$PARTITIONS" ]; then
        echo "WARNING: Kernel sees no partitions on $TARGET_DEV after dd!"
    fi

    for PART_NAME in \$PARTITIONS; do
        # 构造 /dev 下的路径
        PART_DEV="/dev/\$PART_NAME"

        echo "Found partition candidate: \$PART_NAME"

        # ---------------------------------------------------------
        # 核心修复：如果 /dev/xxx 不存在，手动创建设备节点 (mknod)
        # ---------------------------------------------------------
        if [ ! -b "\$PART_DEV" ]; then
            echo "Node \$PART_DEV missing. Creating manually..."
            # 从 /proc/partitions 读取主设备号(major) 和 次设备号(minor)
            # 格式： major minor #blocks name
            read major minor blocks name <<INFO
\$(grep -w "\$PART_NAME" /proc/partitions)
INFO
            if [ -n "\$major" ] && [ -n "\$minor" ]; then
                mknod "\$PART_DEV" b "\$major" "\$minor"
                echo "Created \$PART_DEV (\$major, \$minor)"
            else
                echo "Failed to parse major/minor for \$PART_NAME"
            fi
        fi

        # 尝试挂载
        MOUNT_SUCCESS=false
        if mount "\$PART_DEV" /mnt/target; then
            MOUNT_SUCCESS=true
        elif mount -t ext4 "\$PART_DEV" /mnt/target; then
            MOUNT_SUCCESS=true
        fi

        if [ "\$MOUNT_SUCCESS" = true ]; then
            # 检查是否为根分区标记
            if [ -f /mnt/target/etc/os-release ] || [ -f /mnt/target/etc/debian_version ] || [ -f /mnt/target/bin/bash ]; then
                echo "Found root system at \$PART_DEV"
                ROOT_MOUNTED=true
                break
            else
                echo "\$PART_DEV is not root (os-release not found). Unmounting."
                umount /mnt/target
            fi
        else
            echo "Failed to mount \$PART_DEV"
        fi
    done

    if [ "\$ROOT_MOUNTED" = true ]; then
        echo "Injecting network configuration..."
        mkdir -p /mnt/target/etc/systemd/network

        # 写入 systemd-networkd 配置

        if [ "$USE_DHCP" != true ]; then
            cat > /mnt/target/etc/systemd/network/10-static.network <<NETEOF
[Match]
Name=en* eth*

[Network]
Address=$NET_IP/$CIDR
DNS=$NET_DNS
NETEOF
            if [ -n "$NET_IP6" ]; then
                cat >> /mnt/target/etc/systemd/network/10-static.network <<NETEOF
Address=$NET_IP6/$NET_PREFIX6
DNS=$NET_DNS6
NETEOF
            fi

            cat >> /mnt/target/etc/systemd/network/10-static.network <<NETEOF

[Route]
Gateway=$NET_GW
GatewayOnLink=yes
NETEOF

            if [ -n "$NET_IP6" ]; then
                cat >> /mnt/target/etc/systemd/network/10-static.network <<NETEOF

[Route]
Gateway=$NET_GW6
GatewayOnLink=yes
NETEOF
            fi

            # 确保权限正确
            chmod 644 /mnt/target/etc/systemd/network/10-static.network

            echo "Configuration injected."
        fi

        sync
        umount /mnt/target
    else
        echo "CRITICAL: Could not find any partition containing /etc/os-release!"
        sleep 10
    fi

    echo "Rebooting system..."
    # 强制重启前 Sync
    sync
    sleep 2
    reboot -f
else
    echo "Wget failed or DD failed."
    sleep 60
    exit 1
fi
EOF

chmod +x install_image.sh

# Append the early_command to preseed
# We need to make sure install_image.sh is available in the environment.
# Since we are packing it into initrd, it will be at /install_image.sh (root of initrd)
cat >> preseed.cfg <<EOF
d-i partman/early_command string /install_image.sh
EOF

# 9. Create Custom Initrd
log "Creating custom initrd..."
# We create a separate initrd with our custom files.
# This avoids modifying the signed/compressed original initrd.gz.
echo preseed.cfg | cpio -H newc -o > custom.cpio
echo install_image.sh | cpio -H newc -o -A -F custom.cpio
gzip -f custom.cpio

# 10. Configure GRUB
log "Configuring GRUB..."

# Get UUID of the filesystem containing /boot/reinstall
BOOT_DEV=$(df -P "$WORK_DIR" | awk 'NR==2 {print $1}')
BOOT_UUID=$(blkid -s UUID -o value "$BOOT_DEV")

if [ -z "$BOOT_UUID" ]; then
    error "Could not determine UUID for $BOOT_DEV"
fi

# Determine path relative to the partition root
# If /boot is a separate partition, path is /reinstall/linux
# If /boot is on root, path is /boot/reinstall/linux
# We can find the mount point of BOOT_DEV
MOUNT_POINT=$(findmnt -n -o TARGET "$BOOT_DEV")
REL_PATH="${WORK_DIR#$MOUNT_POINT}"
# Ensure leading slash
if [[ "$REL_PATH" != /* ]]; then REL_PATH="/$REL_PATH"; fi
# Remove double slashes if any
REL_PATH=$(echo "$REL_PATH" | sed 's|//|/|g')

ENTRY_NAME="Debian Reinstall $(date +%Y%m%d-%H%M%S)"

# Add entry to 40_custom
# Note: initrd line loads both the standard initrd and our custom one.
cat >> /etc/grub.d/40_custom <<EOF

menuentry '$ENTRY_NAME' {
    search --no-floppy --fs-uuid --set=root $BOOT_UUID
    linux $REL_PATH/linux auto=true priority=critical file=/preseed.cfg
    initrd $REL_PATH/initrd.gz $REL_PATH/custom.cpio.gz
}
EOF

# Update GRUB
log "Updating GRUB config..."
update-grub

# Set next boot
log "Setting next boot to '$ENTRY_NAME'..."
# We need to find the menu entry number or id.
# grub-reboot expects the name or number.
grub-reboot "$ENTRY_NAME"

log "Done! System is ready to reinstall."
log "Run 'reboot' to start the process."
