#!/bin/bash
# Image cleanup script for Packer provisioner
# Removes unnecessary packages and prepares for image distribution
set -euo pipefail

echo "=== Starting image cleanup ==="

#######################################
# 1. Remove installer leftovers
#######################################
echo "--- Removing installer packages ---"

apt-get -y purge --auto-remove \
    dhcpcd-base \
    installation-report \
    laptop-detect \
    tasksel \
    tasksel-data \
    || true

apt-get -y autoremove --purge
apt-get -y clean

#######################################
# 2. Clear APT cache
#######################################
echo "--- Clearing APT cache ---"

rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*
rm -f /var/cache/apt/*.bin

#######################################
# 3. Remove CDROM/DVD remnants
#######################################
echo "--- Removing optical drive remnants ---"

# Remove cdrom entries from fstab
sed -i '/\/dev\/cdrom/d' /etc/fstab
sed -i '/\/dev\/sr0/d' /etc/fstab
sed -i '/\/media\/cdrom/d' /etc/fstab

# Remove media mount directories
rm -rf /media/cdrom* /media/dvd* /media/floppy*

# Remove cdrom apt source if exists
rm -f /etc/apt/sources.list.d/cdrom.list
sed -i '/^deb cdrom:/d' /etc/apt/sources.list 2>/dev/null || true

#######################################
# 4. Zero free space for compression
#######################################
echo "--- Zeroing free space ---"

dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
rm -f /EMPTY

echo "=== Cleanup complete ==="
