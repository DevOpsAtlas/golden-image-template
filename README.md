# Golden Image Template / 黄金镜像模板

> ⚠️ **WARNING / 警告**
>
> **This repository is a DEMO/EXAMPLE only. DO NOT use it directly in production!**
>
> **本仓库仅为演示示例，请勿直接用于生产环境！**
>
> The repository contains hardcoded passwords, SSH keys, and other sensitive configurations for demonstration purposes. You MUST replace them before any real-world usage.
>
> 本仓库包含硬编码的密码、SSH密钥等敏感配置，仅供演示。在实际使用前，你**必须**替换这些内容。

---

## Introduction / 简介

[![Watch the video](https://img.youtube.com/vi/wki4M4LAwpM/0.jpg)](https://youtu.be/wki4M4LAwpM)

**English:**

This project demonstrates how to build your own Golden Image using Packer and QEMU/KVM. It includes:

1. **Packer Configuration**: Build a minimal, optimized Debian 13 (trixie) image
2. **Reinstall Script**: A powerful script to reinstall the system on a running Debian machine without rescue mode or external media

**中文：**

本项目演示如何使用 Packer 和 QEMU/KVM 构建属于自己的黄金镜像，包含两部分：

1. **Packer 配置**：构建一个最小化、优化过的 Debian 13 (trixie) 镜像
2. **重装脚本**：一个强大的脚本，可在运行中的 Debian 系统上直接重装，无需救援模式或外部介质

---

## Features / 特色

**English:**

- **Automated Image Building**: Full Packer + QEMU/KVM workflow with preseed automation
- **In-place System Reinstall**: Reinstall via GRUB menu injection, no PXE/USB required
- **Smart Network Detection**: Auto-detect IP, gateway, DNS, and IPv6 configuration
- **Cloud-Ready**: QEMU Guest Agent, serial console, cloud-guest-utils included
- **Performance Optimized**: TCP BBR, buffer tuning, VM-specific kernel parameters
- **Security Hardened**: SSH key-only auth, disabled unnecessary services
- **First-Boot Automation**: Auto-generate SSH host keys, expand root partition

**中文：**

- **自动化镜像构建**：完整的 Packer + QEMU/KVM 工作流，配合 preseed 无人值守安装
- **原位系统重装**：通过 GRUB 菜单注入实现重装，无需 PXE/USB
- **智能网络检测**：自动探测 IP、网关、DNS 以及 IPv6 配置
- **云就绪**：内置 QEMU Guest Agent、串口控制台、cloud-guest-utils
- **性能优化**：TCP BBR 拥塞控制、缓冲区调优、VM 专用内核参数
- **安全加固**：仅公钥认证、禁用不必要的服务
- **首次启动自动化**：自动生成 SSH 主机密钥、自动扩展根分区

---

## Dependencies / 依赖

### For Building Images / 构建镜像所需依赖

**English:**

```bash
# Debian/Ubuntu
sudo apt install packer qemu-system-x86 qemu-utils

# Arch Linux
sudo pacman -S packer qemu-full

# Also required:
# - KVM support (check: ls /dev/kvm)
# - At least 2GB RAM and 20GB disk space for building
```

**中文：**

```bash
# Debian/Ubuntu
sudo apt install packer qemu-system-x86 qemu-utils

# Arch Linux
sudo pacman -S packer qemu-full

# 还需要：
# - KVM 支持（检查：ls /dev/kvm）
# - 至少 2GB 内存和 20GB 磁盘空间用于构建
```

### For Local Testing / 本地测试所需依赖

**English:**

```bash
# Libvirt for VM management
sudo apt install libvirt-daemon-system virtinst virt-manager

# Start libvirt service
sudo systemctl enable --now libvirtd
```

**中文：**

```bash
# Libvirt 用于虚拟机管理
sudo apt install libvirt-daemon-system virtinst virt-manager

# 启动 libvirt 服务
sudo systemctl enable --now libvirtd
```

### For reinstall.sh / 重装脚本所需依赖

**English:**

The script will auto-install missing dependencies, but you need:

- Debian 11 (bullseye) or later
- Root privileges
- Network connectivity
- GRUB2 bootloader

**中文：**

脚本会自动安装缺失的依赖，但你需要：

- Debian 11 (bullseye) 或更高版本
- Root 权限
- 网络连接
- GRUB2 引导程序

---

## Build Steps / 构建步骤

### 1. Build the Image / 构建镜像

```bash
# Initialize Packer plugins (first time only)
packer init debian-cloud.pkr.hcl

# Build the image
packer build debian-cloud.pkr.hcl

# Output files:
# - output/kebian-13.qcow2  (QCOW2 format)
# - output/kebian-13.raw.gz (Compressed RAW for distribution)
```

### 2. Test with Libvirt / 使用 Libvirt 测试

```bash
# Copy the image to libvirt storage pool
sudo cp output/kebian-13.qcow2 /var/lib/libvirt/images/kebian-base.qcow2

# Define and start the VM
sudo virsh define libvirt/kebian-low.xml
sudo virsh start kebian-low

# Connect via console
sudo virsh console kebian-low
```

### 3. Use reinstall.sh / 使用重装脚本

**English:**

```bash
# DHCP mode
sudo ./reinstall.sh \
  --image-url https://your-server.com/kebian-13.raw.gz \
  --dhcp

# Static IP mode
sudo ./reinstall.sh \
  --image-url https://your-server.com/kebian-13.raw.gz \
  --ip 192.168.1.100 \
  --netmask 255.255.255.0 \
  --gateway 192.168.1.1 \
  --dns 8.8.8.8

# For Chinese users (use USTC mirror)
sudo ./reinstall.sh \
  --image-url https://your-server.com/kebian-13.raw.gz \
  --cn-mirror \
  --dhcp

# After confirmation, reboot to start reinstallation
sudo reboot
```

**中文：**

```bash
# DHCP 模式
sudo ./reinstall.sh \
  --image-url https://your-server.com/kebian-13.raw.gz \
  --dhcp

# 静态 IP 模式
sudo ./reinstall.sh \
  --image-url https://your-server.com/kebian-13.raw.gz \
  --ip 192.168.1.100 \
  --netmask 255.255.255.0 \
  --gateway 192.168.1.1 \
  --dns 8.8.8.8

# 中国用户（使用中科大镜像源）
sudo ./reinstall.sh \
  --image-url https://your-server.com/kebian-13.raw.gz \
  --cn-mirror \
  --dhcp

# 确认后，重启开始重装
sudo reboot
```

---

## What to Modify for Your Own Use / 使用前需要修改的地方

### 1. Root Password / Root 密码

**File / 文件:** `http/preseed.cfg`

```bash
# Generate a new password hash / 生成新的密码哈希
openssl passwd -6 'YourNewPassword'

# Replace the line / 替换这一行
d-i passwd/root-password-crypted password $6$YOUR_NEW_HASH
```

### 2. SSH Public Key / SSH 公钥

**File / 文件:** `http/preseed.cfg`

```bash
# Find and replace this line / 找到并替换这一行
printf 'ssh-ed25519 YOUR_PUBLIC_KEY your@email.com' > /target/root/.ssh/authorized_keys
```

### 3. Packer SSH Private Key / Packer SSH 私钥

**File / 文件:** `debian-cloud.pkr.hcl`

```hcl
# Change to your key path / 修改为你的密钥路径
ssh_private_key_file = "~/.ssh/your_private_key"
```

### 4. Image Name / 镜像名称

**File / 文件:** `debian-cloud.pkr.hcl`

```hcl
# Change vm_name and output_directory / 修改 vm_name 和 output_directory
vm_name             = "your-image-name.qcow2"
output_directory    = "output"
```

### 5. Installed Packages / 预装软件包

**File / 文件:** `http/preseed.cfg`

```bash
# Modify the package list / 修改软件包列表
d-i pkgsel/include string acpid curl htop vim ... YOUR_PACKAGES
```

### 6. Network Optimization / 网络优化

**File / 文件:** `scripts/setup.sh`

Adjust TCP BBR, buffer sizes, and other kernel parameters as needed.

根据需要调整 TCP BBR、缓冲区大小等内核参数。

---

## Limitations / 限制

### Platform Limitations / 平台限制

| Limitation / 限制  | Description / 说明                                                                                                                                            |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No OpenVZ**      | This image requires full virtualization (KVM/Xen HVM). OpenVZ/LXC containers are NOT supported. / 此镜像需要全虚拟化（KVM/Xen HVM），不支持 OpenVZ/LXC 容器。 |
| **Architecture**   | Only amd64 and arm64 are supported. / 仅支持 amd64 和 arm64 架构。                                                                                            |
| **GRUB2 Required** | reinstall.sh requires GRUB2. Other bootloaders (LILO, syslinux) are not supported. / 重装脚本需要 GRUB2，不支持其他引导程序。                                 |

### reinstall.sh Limitations / 重装脚本限制

| Limitation / 限制       | Description / 说明                                                                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Debian 11+ Only**     | Only works on Debian 11 (bullseye) and later. Ubuntu/other distros are not supported. / 仅适用于 Debian 11 及以后版本，不支持 Ubuntu 等其他发行版。 |
| **Full Disk Overwrite** | The script will COMPLETELY ERASE the target device. All data will be lost! / 脚本会完全擦除目标设备，所有数据将丢失！                               |
| **No RAID/LVM**         | Software RAID and LVM are not tested. Use at your own risk. / 软件 RAID 和 LVM 未经测试，使用需自担风险。                                           |
| **Single Disk**         | Only supports single disk installation. / 仅支持单磁盘安装。                                                                                        |

### Network Limitations / 网络限制

| Limitation / 限制     | Description / 说明                                                                                                                      |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **DHCP for Packer**   | Packer build requires DHCP. Static IP during build is not supported. / Packer 构建需要 DHCP，不支持构建时使用静态 IP。                  |
| **IPv6 DNS Fallback** | If IPv6 DNS cannot be detected, falls back to Google Public DNS (2001:4860:4860::8888). / IPv6 DNS 无法检测时会回退到 Google 公共 DNS。 |

---

## Project Structure / 项目结构

```
golden-image-template/
├── debian-cloud.pkr.hcl      # Packer configuration / Packer 配置
├── reinstall.sh              # System reinstall script / 系统重装脚本
├── files/
│   └── first-boot.service    # Systemd service for first boot / 首次启动服务
├── http/
│   └── preseed.cfg           # Debian preseed configuration / Debian 预设配置
├── libvirt/
│   ├── kebian-low.xml        # Low-spec VM (1vCPU, 512MB) / 低配虚拟机
│   └── kebian-mid.xml        # Mid-spec VM (2vCPU, 4GB) / 中配虚拟机
└── scripts/
    ├── setup.sh              # System configuration / 系统配置
    ├── cleanup.sh            # Image cleanup / 镜像清理
    └── first-boot.sh         # First boot initialization / 首次启动初始化
```

---

## How It Works / 工作原理

### Packer Build Flow / Packer 构建流程

```
1. Boot Debian ISO with preseed.cfg
   启动 Debian ISO 并使用 preseed.cfg 自动安装
        ↓
2. Unattended installation (partitioning, packages, SSH key)
   无人值守安装（分区、软件包、SSH 密钥）
        ↓
3. Run setup.sh (network stack, SSH hardening, kernel tuning)
   运行 setup.sh（网络栈、SSH 加固、内核调优）
        ↓
4. Deploy first-boot.sh and service
   部署首次启动脚本和服务
        ↓
5. Run cleanup.sh (remove caches, zero free space)
   运行 cleanup.sh（清理缓存、填零空闲空间）
        ↓
6. Sysprep (remove SSH host keys, machine-id, logs)
   系统准备（删除 SSH 主机密钥、machine-id、日志）
        ↓
7. Convert to raw.gz for distribution
   转换为 raw.gz 格式以便分发
```

### reinstall.sh Flow / 重装脚本流程

```
1. Validate environment (root, Debian 11+, architecture)
   验证环境（root权限、Debian 11+、架构）
        ↓
2. Parse arguments and auto-detect network config
   解析参数并自动探测网络配置
        ↓
3. Download Debian Installer kernel and initrd
   下载 Debian Installer 内核和 initrd
        ↓
4. Generate preseed.cfg and install_image.sh
   生成 preseed.cfg 和 install_image.sh
        ↓
5. Create custom initrd (cpio archive)
   创建自定义 initrd（cpio 归档）
        ↓
6. Add GRUB menu entry and set as next boot
   添加 GRUB 菜单项并设为下次启动
        ↓
7. User reboots → Debian Installer runs
   用户重启 → Debian Installer 运行
        ↓
8. install_image.sh: dd image, inject network config, reboot
   install_image.sh：dd 镜像、注入网络配置、重启
```

---

## License / 许可证

MIT License

---

## Acknowledgments / 致谢

- [Packer by HashiCorp](https://www.packer.io/)
- [Debian Project](https://www.debian.org/)
- [QEMU/KVM](https://www.qemu.org/)
