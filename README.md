# Build a custom SF Compute image with Packer

A minimal, copyable example. Fork it, edit one file, run two commands.

There are two starting points:

| Start from | Build with | You get |
|---|---|---|
| **An SF Compute base image** (recommended) | `-only='qemu.sfc_base'` | NVIDIA driver, fabric manager, CUDA and the DOCA-OFED / InfiniBand stack already installed and known-good together. You add your software on top. |
| **A stock Ubuntu cloud image** | `-only='qemu.ubuntu'` | A bare Ubuntu image. `install-nvidia.sh` adds a driver and fabric manager. No InfiniBand. |

Prefer the first unless you specifically need to start from bare Ubuntu.
Pairing an NVIDIA driver with a CUDA version, and layering DOCA-OFED
underneath it in the right order, is fiddly and fails in ways that only
show up under load — our base images have that settled.

Both paths produce a **UEFI amd64 raw image**, which is what
`sf images upload` accepts.

## Requirements

Packer 1.9 or newer, QEMU, and OVMF (UEFI firmware). Packer is not in the
Ubuntu archive and was removed from Homebrew core, so install it from
HashiCorp:

```bash
# Linux (Ubuntu/Debian)
wget -O- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y packer qemu-system-x86 qemu-utils ovmf xorriso jq

# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/packer qemu xorriso jq
```

You also need the [`sf` CLI](https://docs.sfcompute.com/) to upload the
result, and roughly 30 GB of free disk.

## Quick start

Put your packages and configuration in **`customize.sh`** — that is the only
file you need to touch. Everything else is boilerplate that makes the image
boot on SF Compute.

```bash
packer init .
packer build -only='qemu.sfc_base' .
```

On Linux with KVM, add `-var 'accelerator=kvm'` — minutes instead of hours.
You need read/write on `/dev/kvm` (`sudo usermod -aG kvm $USER`, then log out
and back in):

```bash
packer build -only='qemu.sfc_base' -var 'accelerator=kvm' .
```

Expect roughly 15 minutes on Linux with KVM, and a few hours on macOS under
emulation. Packer downloads a 3.3 GB base image first. The result is a sparse
20 GiB raw file — it takes far less room on disk, but `sf images upload`
transfers the full 20 GiB. Need more space for your software? Add
`-var 'disk_size=40G'` (the platform caps images at 75 GiB).

`-only` matters: without it Packer builds **both** starting points at once. If
you mistype the name, Packer runs nothing and still exits 0, so check that it
actually printed a build.

Re-running? Packer refuses to overwrite `output/`. Pass `-force`, or
`rm -rf output/` first.

The image lands at `output/sfc_base/ubuntu-24.04-cuda-13.2-custom.raw`.
Upload it:

```bash
sf images upload --name my-image --file output/sfc_base/ubuntu-24.04-cuda-13.2-custom.raw
```

To start from stock Ubuntu instead:

```bash
packer build -only='qemu.ubuntu' -var 'accelerator=kvm' .
```

## Making it yours

Edit **`customize.sh`**. That is the whole customization surface — it
runs as root inside the build VM on both starting points. Everything
else in this repo is boilerplate that makes the resulting image boot
correctly on SF Compute.

If you only ever build on our base images, delete `install-nvidia.sh`, its
`provisioner` block in `build.pkr.hcl`, and the `source "qemu" "ubuntu"`
block — otherwise the repo still offers a path that no longer installs a
driver.

## Choosing a base image

By default the build resolves the current release at build time — there is no
version to keep up to date in this repo. Packer prints the one it picked:

```
Trying https://tiny-llama.sfcc.xyz/v20260930.063326/ubuntu-24.04-cuda-13.2.qcow2
```

To see what is available:

```bash
curl -fsSL https://tiny-llama.sfcc.xyz/latest.json | jq -r '.tag, (.images[].name)'
```

Pick a different image from the release with `base_image_name`:

```bash
packer build -only='qemu.sfc_base' -var 'base_image_name=ubuntu-22.04-cuda-13.1' .
```

**If you need two builds to produce the same bytes, pin the release.** Tracking
the latest means a rebuild next month starts from a different base:

```bash
packer build -only='qemu.sfc_base' -var 'base_image_tag=v20260930.063326' .
```

Integrity needs nothing from you. The release index lists each image's sha256
next to its URL, and the build verifies the download against it — same
document, so the two cannot disagree.

## What the boilerplate is doing

An image is a template that many instances boot from, so it must not
carry anything identifying the machine that built it. `finalize.sh`
handles that: it removes the build-time SSH access, resets the machine
ID, clears cloud-init state, and deletes the SSH host keys. It runs
last, and nothing can run over SSH after it.

The image ships with **no users and a locked root account**. That is
deliberate — SF Compute injects your user and SSH key through its own
cloud-init datasource when an instance launches. The root password in
`cloud-init/user-data` exists only so Packer can log in during the
build, and `finalize.sh` removes it.

## Image requirements

If you build your own template from scratch rather than copying this
one, it must:

- be a **raw**, UEFI, amd64 (x86_64) image — qcow2 is not supported
- resize its root filesystem at boot to fill the instance's disk
- include the `virtio_net` and `mlx5_core` kernel modules (the latter drives the "mlx5Gen Virtual Function" NIC)
- include **cloud-init**, with its network configuration step enabled
- be no larger than 75 GiB

For InfiniBand, it also needs the NVIDIA DOCA-OFED stack (installed
*before* the NVIDIA driver, since `nvidia-peermem` builds against
whatever RDMA symbols are present), `openibd.service` loading the IB
modules at boot, and `nvidia-peermem` loaded at boot for GPUDirect RDMA.
The SF Compute base images ship all of it.

See the [Images documentation](https://docs.sfcompute.com/preview/images)
for the full picture.

## When a build fails

| What you see | What to do |
|---|---|
| `E: Unable to locate package packer` | Packer is not in the Ubuntu archive. See [Requirements](#requirements). |
| `packer init` reports an unknown command | Your Packer predates 1.7. Ubuntu 22.04 ships 1.6.6; install a current one per Requirements. |
| `Output directory 'output/...' already exists` | `packer build -force ...`, or `rm -rf output/`. |
| `Datasource.Execute failed: HTTP request error. Response code: 404` | The tag you pinned has no release index. Drop `-var base_image_tag` to use the current release, or pick a tag from `latest.json`. |
| `invalid checksum: encoding/hex: invalid byte` from `packer validate` | Plain `validate` does not run data sources, so the digest is still unresolved. Use `packer validate -evaluate-datasources .`. |
| `The given key does not identify an element in this collection value` | `base_image_name` is not in that release. List the names with the `jq` command under [Choosing a base image](#choosing-a-base-image). |
| `Could not access KVM kernel module` | No `/dev/kvm`, or you are not in the `kvm` group. Drop `-var 'accelerator=kvm'` to build under emulation. |
| QEMU exits immediately on macOS | Drop `-var 'accelerator=kvm'`; macOS has no KVM. |
| `Could not open '/usr/share/OVMF/...'` | Firmware auto-detection missed yours. Pass `-var 'efi_firmware_code=...' -var 'efi_firmware_vars=...'`; both must be the same variant, so a 4M code file needs a 4M vars file. |
| `Timeout waiting for SSH` | Usually a slow emulated boot. Build on Linux with KVM, or raise `ssh_timeout` in `build.pkr.hcl`. |
| A step you added to `customize.sh` failed | Packer deletes `output/` on failure. Re-run with `-on-error=abort` to keep the VM and disk so you can look. |
| The build succeeded but `packer` printed no build | You mistyped `-only`. Packer exits 0 having run nothing. |

## Files

| File | Purpose |
|---|---|
| `customize.sh` | **Edit this.** Your packages and configuration. |
| `build.pkr.hcl` | Packer template: the two sources and the build. |
| `install-nvidia.sh` | Driver + fabric manager, `qemu.ubuntu` path only. |
| `finalize.sh` | Generalizes the image. Must run last. |
| `cloud-init/user-data` | Build-time-only seed that opens SSH for Packer. |
| `cloud-init/meta-data` | Cloud-init instance metadata. |
