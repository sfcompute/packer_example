# Build a custom SF Compute VM image with Packer.
#
# Two starting points, one build. Pick with -only:
#
#   packer build -only='qemu.sfc_base' .    # from an SF Compute base image
#   packer build -only='qemu.ubuntu'  .    # from a stock Ubuntu cloud image
#
# Both produce a UEFI amd64 raw image under output/, which is what
# `sf images upload` accepts. Edit customize.sh -- that is the only file
# you need to touch.

packer {
  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "base_image_tag" {
  type    = string
  default = "v20260924.213848"

  description = <<-EOT
    Which SF Compute base image release to build on (qemu.sfc_base only).

    This is a pin, on purpose: the same tag gives you the same bytes
    every time. To move to the current release:

      curl -fsSL https://tiny-llama.sfcc.xyz/latest.json | jq -r .tag

    That endpoint also lists every image in the release with its URL,
    SHA256 and size -- see the README.
  EOT
}

variable "base_image_name" {
  type        = string
  default     = "ubuntu-24.04-cuda-13.2"
  description = "Which image within the release (qemu.sfc_base only). Names look like ubuntu-<lts>-cuda-<major.minor>; `curl -fsSL https://tiny-llama.sfcc.xyz/latest.json | jq -r '.images[].name'` lists them."
}

variable "ubuntu_codename" {
  type        = string
  default     = "noble"
  description = "Ubuntu cloud image to build on (qemu.ubuntu only). noble = 24.04 LTS, jammy = 22.04 LTS."
}

variable "nvidia_driver_branch" {
  type        = string
  default     = "590"
  description = <<-EOT
    NVIDIA server driver branch to install (qemu.ubuntu only -- the SF
    Compute base images already ship a driver).

    Must exist in the Ubuntu archive for your codename:
    nvidia-headless-<branch>-server in <codename>-updates/restricted and
    nvidia-fabricmanager-<branch> in <codename>-updates/multiverse. 590
    is present for both jammy and noble.

    Ubuntu may resolve the branch you name forward: as of this writing
    the 590 packages are transitional and depend on their 595
    counterparts, so a build asking for 590 installs 595. That is safe
    rather than a mismatch, because the headless, utils and
    fabric-manager packages are transitional together and land on the
    same branch -- fabric manager refuses to start against a driver
    from a different branch, so they have to move as a set. Check what
    you actually got with `dpkg -l 'nvidia-headless-*'`.
  EOT
}

variable "base_image_checksum" {
  type    = string
  default = ""

  description = <<-EOT
    Override the integrity check on the base image (qemu.sfc_base only).

    Empty (the default) derives it from the tag, as
    "file:<base>/<tag>/SHA256SUMS" -- Packer fetches that file and picks
    the line matching the image it is downloading, exactly as it does
    for Ubuntu's cloud images.

    Releases published before SHA256SUMS existed have no such file and
    Packer fails with a 404. For those, and only those, pass
    -var 'base_image_checksum=none' to skip the check.
  EOT
}

variable "efi_firmware_code" {
  type    = string
  default = ""

  description = <<-EOT
    Path to the OVMF (UEFI) firmware code file. Empty auto-detects.

    Distributions disagree about the filename: Ubuntu 24.04 ships only
    the 4MB variant (OVMF_CODE_4M.fd), 22.04 ships OVMF_CODE.fd, and
    Homebrew's QEMU calls it edk2-x86_64-code.fd. Set this if
    auto-detection doesn't find yours.
  EOT
}

variable "efi_firmware_vars" {
  type        = string
  default     = ""
  description = "Path to the OVMF UEFI variables file. Empty auto-detects. Must match the code file's variant -- pairing a 4M code file with a non-4M vars file does not boot."
}

variable "accelerator" {
  type        = string
  default     = "tcg"
  description = "Set to kvm on Linux for a dramatically faster build. tcg (software emulation) is the portable default and is what you want on macOS."
}

variable "disk_size" {
  type    = string
  default = "20G"

  description = <<-EOT
    Virtual disk size of the produced image.

    QEMU can grow a disk but never shrink it, so this must be at least
    as large as the source image: SF Compute base images are 12G, and
    Ubuntu cloud images are smaller. The platform caps uploads at 75
    GiB. The raw file is sparse, so the apparent size is the ceiling,
    not what you actually store -- but note that uploaders reading
    sequentially transfer the apparent size.
  EOT
}

locals {
  # Public, unauthenticated CDN in front of the R2 bucket the release
  # workflow publishes to.
  sfc_base_url = "https://tiny-llama.sfcc.xyz/${var.base_image_tag}"

  ubuntu_base_url = "https://cloud-images.ubuntu.com/${var.ubuntu_codename}/current"

  # Variable defaults can't reference locals, so the "empty means derive
  # it" fallback lives here rather than on the variable.
  base_image_checksum = var.base_image_checksum != "" ? var.base_image_checksum : "file:${local.sfc_base_url}/SHA256SUMS"

  # Probe for OVMF in the same order as sfc_base_image's test-local.sh,
  # newest layout first. Packer's own default is /usr/share/OVMF/
  # OVMF_VARS.fd, which does not exist on Ubuntu 24.04 -- the build gets
  # as far as booting and then dies on a missing file, so we resolve it
  # here instead. The fallbacks keep the error message pointing at a
  # real path when nothing is found.
  ovmf_code = var.efi_firmware_code != "" ? var.efi_firmware_code : try([
    for p in [
      "/usr/share/OVMF/OVMF_CODE_4M.fd",
      "/usr/share/OVMF/OVMF_CODE.fd",
      "/opt/homebrew/share/qemu/edk2-x86_64-code.fd",
    ] : p if fileexists(p)
  ][0], "/usr/share/OVMF/OVMF_CODE_4M.fd")

  ovmf_vars = var.efi_firmware_vars != "" ? var.efi_firmware_vars : try([
    for p in [
      "/usr/share/OVMF/OVMF_VARS_4M.fd",
      "/usr/share/OVMF/OVMF_VARS.fd",
      "/opt/homebrew/share/qemu/edk2-i386-vars.fd",
    ] : p if fileexists(p)
  ][0], "/usr/share/OVMF/OVMF_VARS_4M.fd")

  # systemd-random-seed.service saves the seed to
  # /var/lib/systemd/random-seed in its ExecStop, which runs during
  # shutdown -- i.e. after every provisioner, so deleting the file in
  # finalize.sh does not stick. Stopping the unit first runs that save
  # once; the file we then delete stays deleted, because an inactive
  # unit is not stopped again on the way down. Neither the Ubuntu cloud
  # images nor the SF Compute base images ship this file, and an image
  # that does gives every instance booted from it the same seed.
  shutdown_command = "systemctl stop systemd-random-seed.service; rm -f /var/lib/systemd/random-seed; shutdown -P now"
}

# ---------------------------------------------------------------------------
# Sources
#
# The two blocks are deliberately near-identical: the only real
# differences are where the disk comes from and what it is called. Both
# boot the downloaded cloud image directly (disk_image = true) and hand
# it a cloud-init seed on a CD labelled "cidata", which is what opens
# the build-time SSH access the provisioners use.
# ---------------------------------------------------------------------------

source "qemu" "sfc_base" {
  # The qcow2 rather than the .raw published alongside it: same image,
  # ~3G instead of ~12G over the wire. format = "raw" below converts on
  # the way out, so what lands in output/ is still raw.
  iso_url = "${local.sfc_base_url}/${var.base_image_name}.qcow2"
  # Released tags publish a SHA256SUMS covering every artifact; Packer
  # picks the line matching the iso_url basename. Releases built before
  # SHA256SUMS existed have no such file -- see base_image_checksum.
  iso_checksum = local.base_image_checksum

  vm_name          = "${var.base_image_name}-custom.raw"
  output_directory = "output/sfc_base"

  disk_image  = true
  format      = "raw"
  disk_size   = var.disk_size
  accelerator = var.accelerator

  # UEFI: the platform requires UEFI images, and booting the build VM
  # the same way the instance will is the point of the exercise.
  efi_boot          = true
  efi_firmware_code = local.ovmf_code
  efi_firmware_vars = local.ovmf_vars
  headless          = true
  disable_vnc       = true
  memory            = 2048
  cpus              = 2

  cd_files = ["./cloud-init/meta-data", "./cloud-init/user-data"]
  cd_label = "cidata"
  # Belt and braces for cloud-init's datasource detection: the CD label
  # alone is usually enough, but the SMBIOS hint makes NoCloud
  # unambiguous on a freshly generalized image.
  qemuargs = [["-smbios", "type=1,serial=ds=nocloud"]]

  ssh_username     = "root"
  ssh_password     = "packer"
  ssh_timeout      = "20m"
  shutdown_command = local.shutdown_command
}

source "qemu" "ubuntu" {
  iso_url      = "${local.ubuntu_base_url}/${var.ubuntu_codename}-server-cloudimg-amd64.img"
  iso_checksum = "file:${local.ubuntu_base_url}/SHA256SUMS"

  vm_name          = "ubuntu-${var.ubuntu_codename}-custom.raw"
  output_directory = "output/ubuntu"

  disk_image  = true
  format      = "raw"
  disk_size   = var.disk_size
  accelerator = var.accelerator

  # UEFI: the platform requires UEFI images, and booting the build VM
  # the same way the instance will is the point of the exercise.
  efi_boot          = true
  efi_firmware_code = local.ovmf_code
  efi_firmware_vars = local.ovmf_vars
  headless          = true
  disable_vnc       = true
  memory            = 2048
  cpus              = 2

  cd_files = ["./cloud-init/meta-data", "./cloud-init/user-data"]
  cd_label = "cidata"
  qemuargs = [["-smbios", "type=1,serial=ds=nocloud"]]

  ssh_username     = "root"
  ssh_password     = "packer"
  ssh_timeout      = "20m"
  shutdown_command = local.shutdown_command
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

build {
  sources = [
    "source.qemu.sfc_base",
    "source.qemu.ubuntu",
  ]

  # Only the stock-Ubuntu path needs this: an SF Compute base image
  # already ships the driver, fabric manager, CUDA and the DOCA-OFED
  # stack that InfiniBand requires.
  provisioner "shell" {
    only   = ["qemu.ubuntu"]
    script = "install-nvidia.sh"
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "NVIDIA_DRIVER_BRANCH=${var.nvidia_driver_branch}",
    ]
  }

  # Your changes. This is the file to edit.
  provisioner "shell" {
    script           = "customize.sh"
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }

  # Must stay last: it removes the build-time SSH access and wipes
  # per-machine identity, so nothing can run over SSH after it.
  provisioner "shell" {
    script           = "finalize.sh"
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
  }
}
