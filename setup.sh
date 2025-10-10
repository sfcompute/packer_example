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

rm /etc/ssh/sshd_config.d/*
usermod -p '!' root
