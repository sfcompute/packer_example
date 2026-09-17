#!/usr/bin/env bash
#
# ===========================================================================
#  THIS IS THE FILE YOU EDIT.
#
#  Everything else in this repo is boilerplate that makes the image boot
#  on SF Compute. Put your packages, config and files here.
#
#  Runs as root inside the build VM, on both starting points.
# ===========================================================================

set -euo pipefail

apt-get update

# ---- your packages --------------------------------------------------------

apt-get install -y --no-install-recommends \
  htop \
  tmux \
  ;

# ---- your configuration ---------------------------------------------------

# Anything you can do on a running Ubuntu box, you can do here. A few
# examples, commented out:

# Bake in a config file:
#   install -D -m 0644 /dev/stdin /etc/myapp/config.toml <<'CONF'
#   log_level = "info"
#   CONF

# Enable a service so it starts on every boot (start it at boot, not
# here -- the build VM has no GPUs and no network fabric):
#   systemctl enable myapp.service

# Install Python deps into a venv your jobs can use:
#   python3 -m venv /opt/venv
#   /opt/venv/bin/pip install --no-cache-dir torch

# ---- keep the image small -------------------------------------------------
# Package caches would otherwise be baked into every copy of the image.

apt-get clean
rm -rf /var/lib/apt/lists/*
