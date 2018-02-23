{ nixpkgs ? <nixpkgs> # TODO peg revision once stable
}:
let lib = import (nixpkgs + "/lib");
    crossSystem = lib.systems.examples.riscv64;
    crossPkgs = import nixpkgs { inherit crossSystem; };
    pkgs = import nixpkgs {};
    self =
      { busybox = lib.overrideDerivation
          (crossPkgs.busybox.override { enableStatic = true; })
          (orig:
            { nativeBuildInputs = (orig.nativeBuildInputs or []) ++
                [ crossPkgs.removeReferencesTo ];

              postFixup = (orig.postFixup or "") + ''
                remove-references-to -t ${crossPkgs.stdenv.cc.libc} \
                 $out/bin/busybox
              '';

              allowedReferences = [];
            });
        kernel = crossPkgs.linux_riscv;
        initrd-modules = pkgs.makeModulesClosure
          { inherit (self) kernel;
            firmware = null;
            rootModules = [ "virtio_scsi" "btrfs" "crc32c" "sd_mod" "virtio_mmio" ];
          };
        init = pkgs.writeScriptBin "init" ''
          #!${self.busybox}/bin/sh
          mount -t proc proc /proc
          mount -t sysfs sysfs /sys
          mount -t devtmpfs devtmpfs /dev
          modprobe sd_mod
          modprobe virtio_mmio
          modprobe virtio_scsi
          modprobe crc32c
          modprobe btrfs
          exec -a init ash
        '';
        initrd = pkgs.makeInitrd
          { contents =
              [ { object = "${self.init}/bin/init";
                  symlink = "/init";
                }
                { object = "${self.busybox}/bin";
                  symlink = "/bin";
                }
                { object = "${self.initrd-modules}/lib/modules";
                  symlink = "/lib/modules";
                }
              ];
          };
        bbl = crossPkgs.riscv-pk-with-kernel;
        qemu = pkgs.qemu-riscv;
        run-vm = pkgs.writeShellScriptBin "run-vm"
          ''
            declare -r mem="''${QEMU_MEMORY_SIZE:2G}"
            declare -r cmd="''${QEMU_KERNEL_CMDLINE:console=ttyS0}"
            exec -a qemu-system-riscv64 \
              ${self.qemu}/bin/qemu-system-riscv64 -nographic \
              -machine virt -m "$mem" -append "$cmd" \
              -kernel ${self.bbl}/bin/bbl \
              -initrd ${self.initrd}/initrd "$@"
          '';
      };
in self
