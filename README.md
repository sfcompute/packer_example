# Build a custom SF Compute image with Packer

A minimal, copyable example. Fork it, edit one file, run one command.

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

```bash
# Linux
sudo apt-get install -y packer qemu-system-x86 qemu-utils ovmf genisoimage

# macOS
brew install packer qemu xorriso
```

On macOS the VM runs under software emulation and the build is slow. On
Linux, add `-var 'accelerator=kvm'` for a hardware-accelerated build.

## Quick start

```bash
packer init .
packer build -only='qemu.sfc_base' -var 'accelerator=kvm' .
```

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

If you only ever build on our base images, delete `install-nvidia.sh`
and its `provisioner` block in `build.pkr.hcl`.

## Choosing a base image

`build.pkr.hcl` pins a specific release by default, so repeated builds
reproduce the same bytes. To see what is current:

```bash
curl -fsSL https://tiny-llama.sfcc.xyz/latest.json | jq -r '.tag, (.images[].name)'
```

`latest.json` is the published index of the newest release: the tag, and
every image in it with its URL, SHA256 and size. Point the build at one
with `-var`:

```bash
packer build -only='qemu.sfc_base' \
  -var 'base_image_tag=v20261001.120000' \
  -var 'base_image_name=ubuntu-22.04-cuda-13.1' .
```

Then pin that tag in `build.pkr.hcl` so your builds stay reproducible.

Integrity is checked against the `SHA256SUMS` published alongside each
release; Packer fetches it and picks the line matching the image it is
downloading. Releases published before `SHA256SUMS` existed don't have
one, and Packer will fail with a 404 — for those, pass
`-var 'base_image_checksum=none'`.

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
- include drivers for **virtio-net** and **mlx5Gen Virtual Function**
- include **cloud-init**, with its network configuration step enabled
- be no larger than 75 GiB

For InfiniBand, it also needs the NVIDIA DOCA-OFED stack (installed
*before* the NVIDIA driver, since `nvidia-peermem` builds against
whatever RDMA symbols are present), `openibd.service` loading the IB
modules at boot, and `nvidia-peermem` loaded at boot for GPUDirect RDMA.
The SF Compute base images ship all of it.

See the [Images documentation](https://docs.sfcompute.com/preview/images)
for the full picture.

## Files

| File | Purpose |
|---|---|
| `customize.sh` | **Edit this.** Your packages and configuration. |
| `build.pkr.hcl` | Packer template: the two sources and the build. |
| `install-nvidia.sh` | Driver + fabric manager, `qemu.ubuntu` path only. |
| `finalize.sh` | Generalizes the image. Must run last. |
| `cloud-init/user-data` | Build-time-only seed that opens SSH for Packer. |
| `cloud-init/meta-data` | Cloud-init instance metadata. |
