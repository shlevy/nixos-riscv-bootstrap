{ lib, pkgs, config, ... }:
let resize = pkgs.runCommandCC "resize" {} ''
      mkdir -p $out/bin
      ${pkgs.stdenv.cc.targetPrefix}cc ${./resize.c} -O3 -o $out/bin/resize-disk
      fixupPhase
    '';

    ugh = pkgs.writeShellScriptBin "retain-deps" ''
      echo "The extra-utils are at ${config.system.build.extraUtils}" >&2
    '';
in
{ nixpkgs.crossSystem = lib.systems.examples.riscv64;

  boot.loader.grub.enable = false;
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux_riscv;
  boot.initrd.extraUtilsCommands = ''
    cp -a ${resize}/bin/resize-disk $out/bin
  '';
  boot.initrd.postMountCommands = ''
    if [ -f /mnt-root/needs-resize ]; then
      PATH=$systemConfig/sw/bin:$PATH resize-disk
    fi
  '';

  environment.noXlibs = true;
  environment.systemPackages = [ pkgs.gptfdisk ugh ];
  # gobject-introspection apparently can't cross-compile without running host code: http://nicola.entidi.com/post/cross-compiling-gobject-introspection/
  # polkit brings in gobject-introspection
  security.polkit.enable = false;
  # udisks2 brings in polkit
  services.udisks2.enable = false;
  fileSystems."/" =
    { label = "root";
      fsType = "btrfs";
    };

  # texinfo fails to cross-build at the moment.
  programs.info.enable = false;

  nix.package = pkgs.nixUnstable;
  nix.sshServe =
    { enable = true;
      keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID/fJqgjwPG7b5SRPtCovFmtjmAksUSNg3xHWyqBM4Cs shlevy@shlevy-laptop" ];
      protocol = "ssh-ng";
    };
  nix.trustedUsers = [ "nix-ssh" ];

  system.boot.loader.kernelFile = "vmlinux";

  users.extraUsers.root.initialHashedPassword = "";
}
