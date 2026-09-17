#!/usr/bin/env bash
#
# GPU support for the stock-Ubuntu starting point (qemu.ubuntu) only.
#
# The SF Compute base images already ship all of this, which is why this
# script doesn't run for qemu.sfc_base. If you only ever build on our
# base images, you can delete this file and its provisioner block.
#
# Scope: driver + fabric manager, enough for `nvidia-smi` to work on a
# GPU instance. It deliberately does NOT set up InfiniBand -- that needs
# the NVIDIA DOCA-OFED stack installed *before* the driver, plus
# nvidia-peermem loaded at boot for GPUDirect RDMA. Getting that ordering
# wrong produces an image whose RDMA silently doesn't work. Start from an
# SF Compute base image instead of reproducing it.

set -euo pipefail

: "${NVIDIA_DRIVER_BRANCH:?NVIDIA_DRIVER_BRANCH not set (passed by build.pkr.hcl)}"

echo "==> Installing NVIDIA driver branch ${NVIDIA_DRIVER_BRANCH}"

apt-get update

# nvidia-headless-<branch>-server lives in <codename>-updates/restricted;
# nvidia-fabricmanager-<branch> lives in <codename>-updates/multiverse.
# nvidia-modprobe matters more than it looks: the headless metapackage
# does not pull it in, and it is what lets fabric manager create the
# /dev/nvidia-nvswitch* nodes on NVSwitch/HGX hosts. Without it,
# multi-GPU NVLink P2P and NCCL break quietly.
apt-get install -y --no-install-recommends \
  "nvidia-headless-${NVIDIA_DRIVER_BRANCH}-server" \
  "nvidia-utils-${NVIDIA_DRIVER_BRANCH}-server" \
  "nvidia-fabricmanager-${NVIDIA_DRIVER_BRANCH}" \
  nvidia-modprobe \
  ;

# Enabled, not started: the build VM has no GPU, so starting it here
# would just fail. It comes up on first boot on a real instance.
systemctl enable nvidia-fabricmanager.service

# Confirm the binary landed. Don't run nvidia-smi itself -- even
# `--version` opens the driver and exits non-zero with no GPU present.
command -v nvidia-smi

apt-get clean
rm -rf /var/lib/apt/lists/*
