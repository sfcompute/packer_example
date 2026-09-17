#!/usr/bin/env bash
#
# Generalize the image. MUST run last.
#
# A VM image is a template that many instances boot from, so anything
# identifying this particular build VM has to go: SSH host keys, the
# machine ID, cloud-init's record of having already run. Leave them in
# and every instance from this image shares one identity.
#
# This also tears down the build-time root SSH access that
# cloud-init/user-data opened, so no provisioner can run over SSH after
# this point -- only Packer's shutdown_command, which reuses the live
# session.

set -euo pipefail

echo "==> Removing build-time SSH access"
# Drops the PasswordAuthentication/PermitRootLogin override the
# cloud-init seed wrote, and re-locks root. SF Compute injects the
# customer's user and SSH key via its own cloud-init datasource at
# launch, so the shipped image needs no login of its own.
rm -f /etc/ssh/sshd_config.d/*
usermod -p '!' root

echo "==> Resetting per-machine identity"
# 'uninitialized' is systemd's explicit first-boot trigger: it
# regenerates a fresh machine-id on the next boot. An empty file would
# work too, but a *populated* one is never regenerated -- which is how
# every instance ends up sharing an identity.
printf 'uninitialized\n' > /etc/machine-id
cloud-init clean --logs

shopt -s dotglob
rm -rf \
  /tmp/* \
  /var/tmp/* \
  /etc/hostname \
  /etc/machine-info \
  /etc/ssh/ssh_host_* \
  /var/lib/dbus/machine-id \
  /root/.bash_history \
  ;

# /var/lib/systemd/random-seed is deliberately not in that list: systemd
# rewrites it during shutdown, after this script has run. It is handled
# by shutdown_command in build.pkr.hcl instead.

# The build VM's cloud-init wrote a DHCP netplan keyed to this VM's NIC
# name. On an instance with a different NIC, that file matches nothing
# and the instance boots with no network. `cloud-init clean` doesn't
# remove rendered netplan, so do it here.
rm -f /etc/netplan/50-cloud-init.yaml

echo "==> Image finalized"
