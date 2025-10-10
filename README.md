# Example Ubuntu Jammy VM Image

This is a small example of building an image with packer that one can use with
SFC's custom (user provided) VM images system. After building, and starting a VM
with this image on the Nvidia h100 platform, you should be able to run
`nvidia-smi` within the VM and see the GPUs listed.

# Building

After installing the necessary dependencies (QEMU, optionally KVM, and packer):

```bash
packer build ./jammy.pkr.hcl
```

The built VM image will be located at `output/ubuntu_jammy.img`.

# Customizing

Basic customizations can be added to `setup.sh` if the reader wants to install
additional packages and doesn't need to change their Linux distribution. See the
line marked `# USER CHANGES HERE` for the recommended location.
