packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:677c4d57aa034dc192b5191870141057574c1b05df2b9569c0ee08aa4e32125d"
}

variable "disk_size" {
  type    = string
  default = "2G"
}

variable "memory" {
  type    = number
  default = 1024
}

variable "cpus" {
  type    = number
  default = 1
}

variable "output_directory" {
  type    = string
  default = "output"
}

variable "vm_name" {
  type    = string
  default = "kebian-13"
}

source "qemu" "debian" {
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  output_directory = var.output_directory
  vm_name          = "${var.vm_name}.qcow2"

  # VM hardware settings
  memory      = var.memory
  cpus        = var.cpus
  disk_size   = var.disk_size
  format      = "qcow2"
  accelerator = "kvm"

  # Network
  net_device     = "virtio-net"
  disk_interface = "virtio"

  # HTTP server for preseed
  http_directory = "http"

  # Boot configuration
  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "auto ",
    "url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "hostname=kebian ",
    "domain=localdomain ",
    "interface=auto ",
    "priority=critical ",
    "<enter>"
  ]

  # SSH settings for Packer to connect after install
  ssh_username         = "root"
  ssh_private_key_file = pathexpand("~/.ssh/devopsatlas")
  ssh_timeout          = "30m"
  ssh_port             = 22

  # Shutdown
  shutdown_command = "poweroff"

  # Headless mode (set to false for debugging)
  headless = true

  # QEMU display (for debugging, use -display gtk or sdl)
  qemuargs = [
    ["-cpu", "host"],
    ["-smp", "cpus=${var.cpus}"],
    ["-m", "${var.memory}M"]
  ]
}

build {
  sources = ["source.qemu.debian"]

  # 1. System configuration (network stack, SSH, kernel tuning)
  provisioner "shell" {
    script = "scripts/setup.sh"
  }

  # 2. Deploy first-boot script
  provisioner "file" {
    source      = "scripts/first-boot.sh"
    destination = "/usr/local/bin/first-boot.sh"
  }

  provisioner "shell" {
    inline = ["chmod +x /usr/local/bin/first-boot.sh"]
  }

  # 3. Deploy and enable first-boot service
  provisioner "file" {
    source      = "files/first-boot.service"
    destination = "/etc/systemd/system/first-boot.service"
  }

  provisioner "shell" {
    inline = ["systemctl enable first-boot.service"]
  }

  # 4. System cleanup
  provisioner "shell" {
    script = "scripts/cleanup.sh"
  }

  # 5. Final sysprep (prepare for distribution)
  provisioner "shell" {
    inline = [
      "# Remove SSH host keys (regenerated on first boot)",
      "rm -f /etc/ssh/ssh_host_*",

      "# Clear machine-id (regenerated on first boot)",
      "truncate -s 0 /etc/machine-id",
      "rm -f /var/lib/dbus/machine-id",

      "# Clear logs",
      "journalctl --rotate",
      "journalctl --vacuum-time=1s",
      "find /var/log -type f -exec truncate -s 0 {} \\;",

      "# Clear bash history",
      "unset HISTFILE",
      "rm -f /root/.bash_history",

      "# Clear temporary files",
      "rm -rf /tmp/* /var/tmp/*",

      "# Sync and clear caches",
      "sync",
      "echo 3 > /proc/sys/vm/drop_caches || true"
    ]
  }

  # Convert qcow2 to raw.gz (compressed, no intermediate raw file)
  post-processor "shell-local" {
    inline = [
      "echo '=== Converting qcow2 to raw.gz ==='",
      "qemu-img convert -f qcow2 ${var.output_directory}/${var.vm_name}.qcow2 -O raw ${var.output_directory}/${var.vm_name}.raw",
      "gzip ${var.output_directory}/${var.vm_name}.raw",
      "echo '=== Done ==='",
      "ls -lh ${var.output_directory}/"
    ]
  }
}
