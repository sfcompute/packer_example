packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

source "qemu" "ubuntu" {
  cd_files         = ["./cloud-init/*"]
  cd_label         = "cidata"
  disable_vnc      = true
  disk_image       = true
  disk_size        = "8G"
  efi_boot         = true
  format           = "raw"
  headless         = "true"
  iso_checksum     = "file:https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS"
  iso_url          = "http://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  output_directory = "output"
  shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
  ssh_password     = "password"
  ssh_username     = "root"
  vm_name          = "ubuntu_jammy.img"
}

build {
  sources = ["source.qemu.ubuntu"]

  provisioner "shell" {
    script = "setup.sh"
  }
}
