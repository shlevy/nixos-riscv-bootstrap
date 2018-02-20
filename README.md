nixos-riscv-bootstrap
======================

Nix expressions to help bootstrap our way to full RISC-V support on
NixOS.

Running the VM
----------------

`run-vm` will build and run the VM described in [default.nix]. It
requires that you have [Nix] installed and a recent [nixpkgs] checkout
available in you [$NIX_PATH].

[default.nix]: ./default.nix
[Nix]: https://nixos.org/nix
[nixpkgs]: https://nixos.org/nixpkgs
[$NIX_PATH]: https://nixos.org/nix/manual/#env-NIX_PATH
