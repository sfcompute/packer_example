#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y auto-apt-proxy

apt-get -y upgrade
apt-get -y dist-upgrade

apt-get install -y \
  nvidia-driver-565-server-open \
  nvidia-fabricmanager-565 \
;

# USER CHANGES HERE

# Disable root ssh, and console access
rm /etc/ssh/sshd_config.d/*
usermod -p '!' root

# Do basic cleanup (virt-sysprep can be used to further shrink the image) and
# remove per-machine state.
apt-get clean
shopt -s dotglob
rm -rf \
  /tmp/* \
  /var/tmp/* \
  \
  /etc/machine-id \
  /etc/ssh/ssh_host* \
  /var/lib/dbus/machine-id \
;
