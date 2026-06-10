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

# Currently, it takes a while to time out (in the newer networking set up for
# SFC VMs) while waiting for non-existent proxy servers to reply and
# `auto-apt-proxy` is intended for improving build times.
apt-get -y remove auto-apt-proxy

# Do basic cleanup (virt-sysprep can be used to further shrink the image) and
# remove per-machine state.
apt-get clean

printf 'uninitialized\n' >/etc/machine-id
cloud-init clean --logs

shopt -s dotglob
rm -rf \
  /tmp/* \
  /var/tmp/* \
  \
  /etc/hostname \
  /etc/machine-info \
  /etc/ssh/ssh_host* \
  /var/lib/dbus/machine-id \
  /var/lib/systemd/random-seed \
;
