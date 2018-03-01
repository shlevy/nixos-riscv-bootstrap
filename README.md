nixos-riscv-bootstrap
======================

!!! This readme is out of date !!!

Nix expressions to help bootstrap our way to full RISC-V support on
NixOS.

Requirements
------------
The scripts in this project require that you have [Nix] installed and
a recent [nixpkgs] checkout available in your [$NIX_PATH].

Initializing the base Nix store image
---------------------------------------
The VM needs an image to mount as the Nix store, which uses as its
base an image containing core packages such as Nix itself and busybox.
The `make-image` script can be used to create an image on top of the
base image, but because images cannot be rebased you must re-create
the image if you want to pick up changes to the core package.

If you run the VM with no image, it will create one for you.

Running the VM
----------------

`run-vm` will build and run the VM described in [default.nix]. You
will be dropped into a busybox shell with the core packages available.
You can specify extra flags to the qemu-system command line as
arguments to `run-vm`

[default.nix]: ./default.nix
[Nix]: https://nixos.org/nix
[nixpkgs]: https://nixos.org/nixpkgs
[$NIX_PATH]: https://nixos.org/nix/manual/#env-NIX_PATH
