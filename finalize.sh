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
# Name the two files the build creates rather than globbing the directory.
# 10-packer.conf is the seed's runcmd override; 50-cloud-init.conf is what
# cloud-init writes for the seed's `ssh_pwauth: true`. A glob would also take
# 60-cloudimg-settings.conf, which Ubuntu's cloud image ships containing
# `PasswordAuthentication no` -- and sshd_config only has that directive
# commented out, so removing the drop-in silently falls back to OpenSSH's
# default of yes. It would also delete anything you add in customize.sh.
rm -f \
  /etc/ssh/sshd_config.d/10-packer.conf \
  /etc/ssh/sshd_config.d/50-cloud-init.conf
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
