#!/bin/bash
# First boot initialization script
# Runs once on first boot (before ssh.service), then disables itself
set -euo pipefail

echo "=== First boot initialization ==="

#######################################
# 1. Generate machine-id if empty
#######################################
if [ ! -s /etc/machine-id ]; then
    echo "--- Generating machine-id ---"
    systemd-machine-id-setup
fi

#######################################
# 2. Generate SSH host keys and start service
#######################################
echo "--- Setting up SSH ---"

# Generate host keys
ssh-keygen -A

# Enable and start SSH service (was disabled in image build)
systemctl enable --now ssh.service || true

#######################################
# 3. Grow root partition and filesystem
#######################################
# A. 获取设备信息，并使用 xargs 去除可能存在的首尾空格
ROOT_PART=$(findmnt / -n -o SOURCE | xargs)
DISK_NAME=$(lsblk -no pkname "$ROOT_PART" | xargs)
PART_NUM=$(lsblk -no partn "$ROOT_PART" | xargs)
DISK_DEV="/dev/$DISK_NAME"

echo "Resizing: Device=$DISK_DEV, Partition=$PART_NUM, Root=$ROOT_PART"

# B. 执行扩容
# growpart 可能会返回非0值(如果已经扩容过)，所以加 || true 防止脚本意外退出
growpart "$DISK_DEV" "$PART_NUM" || echo "growpart output code: $?"
partprobe "$DISK_DEV" || echo "partprobe skipped"
resize2fs "$ROOT_PART" || echo "resize2fs failed"

#######################################
# 4. Self destroy
#######################################
echo "--- First boot complete ---"

systemctl disable first-boot.service 2>/dev/null || true
rm -f /etc/systemd/system/first-boot.service
rm -f /usr/local/bin/first-boot.sh

echo "=== First boot initialization finished ==="
