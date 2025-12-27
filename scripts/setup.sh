#!/bin/bash
# System configuration script for Packer provisioner
# Handles: network stack, SSH hardening, kernel tuning, KVM optimization
set -euo pipefail

echo "=== Starting system configuration ==="

#######################################
# 1. Switch to systemd-networkd stack
#######################################
echo "--- Configuring network stack ---"

# Remove ifupdown (Debian installer default)
apt-get -y purge ifupdown || true

# Enable systemd network services
systemctl enable systemd-networkd
systemctl enable systemd-resolved

# Create networkd configuration for all ethernet interfaces
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-ethernet.network << 'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF

# Point resolv.conf to systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Clean up legacy network config
rm -f /etc/network/interfaces
rm -f /etc/network/interfaces.d/*

#######################################
# 2. SSH hardening
#######################################
echo "--- Hardening SSH ---"

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# SSH will be enabled by first-boot after generating host keys
systemctl disable ssh

#######################################
# 3. GRUB configuration (fast boot + serial console)
#######################################
echo "--- Configuring GRUB ---"

cat > /etc/default/grub.d/cloud.cfg << 'EOF'
# Fast boot
GRUB_TIMEOUT=1
GRUB_RECORDFAIL_TIMEOUT=1

# Serial console support (for virsh console, cloud provider console)
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"

# Kernel boot parameters
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8 net.ifnames=0 biosdevname=0"

# Disable graphical boot
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX quiet"

# Disable OS prober (single-boot system)
GRUB_DISABLE_OS_PROBER=true
EOF

update-grub

#######################################
# 4. Serial console getty
#######################################
echo "--- Enabling serial console ---"

systemctl enable serial-getty@ttyS0.service

#######################################
# 5. Kernel parameters (network + VM optimization)
#######################################
echo "--- Configuring kernel parameters ---"

cat > /etc/sysctl.d/99-cloud.conf << 'EOF'
# TCP BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Network buffer optimization
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Connection tracking
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# VM optimization
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
EOF

# Ensure BBR module loads at boot
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf

#######################################
# 6. Filesystem optimization (noatime)
#######################################
echo "--- Optimizing fstab ---"

# Add noatime to root filesystem if not present
if grep -q "/ .*ext4" /etc/fstab && ! grep -q "noatime" /etc/fstab; then
    sed -i 's|\(.*/ .*ext4.*\)defaults\(.*\)|\1defaults,noatime\2|' /etc/fstab
fi

#######################################
# 7. Journald configuration
#######################################
echo "--- Configuring journald ---"

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/image.conf << 'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=32M
ForwardToSyslog=no
EOF

#######################################
# 8. Disable unnecessary services
#######################################
echo "--- Disabling unnecessary services ---"

systemctl disable ModemManager.service 2>/dev/null || true
systemctl disable bluetooth.service 2>/dev/null || true
systemctl mask systemd-random-seed.service 2>/dev/null || true

# Disable apt auto-update timers
systemctl mask apt-daily.timer apt-daily-upgrade.timer

#######################################
# 9. Enable essential services
#######################################
echo "--- Enabling essential services ---"

systemctl enable qemu-guest-agent
systemctl enable acpid

echo "=== System configuration complete ==="
