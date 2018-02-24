{ nixpkgs ? <nixpkgs> # TODO peg revision once stable
, imageSize ? "2G"
}:
let lib = import (nixpkgs + "/lib");
    crossSystem = lib.systems.examples.riscv64;
    crossPkgs = import nixpkgs { inherit crossSystem; };
    pkgs = import nixpkgs {};
    closureInfo = pkgs.callPackage ./closure-info.nix {};
    busybox =
      lib.overrideDerivation
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
        { inherit kernel;
          firmware = null;
          rootModules = [ "virtio_scsi" "virtio_mmio" "sd_mod"
                          "btrfs" "crc32c"
                        ];
        };
      init = pkgs.writeScriptBin "init" ''
        #!${busybox}/bin/sh
        mount -t proc proc /proc
        mount -t sysfs sysfs /sys
        mount -t devtmpfs devtmpfs /dev
        modprobe sd_mod
        modprobe virtio_mmio
        modprobe virtio_scsi
        modprobe crc32c
        modprobe btrfs

        profile="$(grep -o 'profile=[^ ]*' /proc/cmdline | \
          sed 's/^profile=//')"
        export PATH="$profile/bin":$PATH

        mkdir -p /nix-cleanup/nix
        mount --bind /nix /nix-cleanup/nix
        mount /dev/sda1 /nix

        if [ -f /nix/needs-resize ]; then
          echo "Resizing /nix to the full disk space..." >&2
          sgdisk --clear --new 1 --change-name=1:"${base-image.name}" /dev/sda
          /nix-cleanup/${busybox}/bin/umount /nix
          partprobe /dev/sda
          mount /dev/sda1 /nix
          btrfs filesystem resize max /nix
          sync
          rm /nix/needs-resize
        fi

        rm -fR /nix-cleanup/nix/*
        umount /nix-cleanup/nix
        rmdir /nix-cleanup/nix
        rmdir /nix-cleanup/

        unlink /bin
        ln -sf "$profile"/bin /
        unlink /lib/modules
        rmdir /lib
        ln -sf "$profile"/lib /lib
        unlink /init
        exec -a init ash
      '';
      initrd = pkgs.makeInitrd
        { contents =
            [ { object = "${init}/bin/init";
                  symlink = "/init";
              }
              { object = "${busybox}/bin";
                symlink = "/bin";
              }
              { object = "${initrd-modules}/lib/modules";
                symlink = "/lib/modules";
              }
            ];
        };
      bbl = crossPkgs.riscv-pk.override
        { payload = "${kernel}/vmlinux"; };
      qemu = pkgs.qemu-riscv;
      base-profile = pkgs.buildEnv
        { name = "nixos-riscv-bootstrap-base-profile";
          paths =
            map (p: crossPkgs.${p}) [ "nixUnstable"
                                      "gptfdisk"
                                      "btrfs-progs"
                                    ] ++ [ kernel busybox ];
        };
      image-closure = closureInfo { rootPaths = [ base-profile ]; };
      base-image =
        pkgs.vmTools.runInLinuxVM (pkgs.runCommand "riscv-base-nix-image"
          { nativeBuildInputs = (map (p: pkgs.${p})
              [ "btrfs-progs" "gptfdisk" "nixUnstable" "utillinux" ]);
            preVM = ''
              diskImage=$name.qcow2

              imageSize=$(expr $(cat ${image-closure}/total-nar-size) + 200000000)
              ${qemu}/bin/qemu-img create -f qcow2 $diskImage $imageSize
            '';
            postVM = ''
              mkdir -p $out
              mv $diskImage $out
            '';
          }
          ''
            sgdisk --new 1 --change-name=1:"$name" /dev/vda
            mkfs.btrfs --label nix /dev/vda1
            mkdir -p /mnt/nix
            mount /dev/vda1 /mnt/nix
            nix-store --load-db <${image-closure}/registration
            nix-store -r ${base-profile} --option store /mnt \
              --option substituters "/?trusted=true"
            touch /mnt/nix/needs-resize
            umount /mnt/nix
          '');
    self =
      { make-image = pkgs.writeShellScriptBin "make-image"
          ''
            declare -r file="''${1-nix-store-image.qcow2}"
            declare -r size="''${2-${imageSize}}"
            exec -a qemu-img ${qemu}/bin/qemu-img create -f qcow2 \
              -b ${base-image}/riscv-base-nix-image.qcow2 "$file" \
              $size
          '';
        run-vm = pkgs.writeShellScriptBin "run-vm"
          ''
            set -euo pipefail
            declare -r image="''${NIX_STORE_IMAGE-nix-store-image.qcow2}"
            if [ ! -f "$image" ]; then
              echo "No nix store image, creating one sized ${imageSize}...">&2
              ${self.make-image}/bin/make-image "$image" ${imageSize}
            fi
            declare -r mem="''${QEMU_MEMORY_SIZE-2G}"
            declare -r cmd="console=ttyS0 profile=${base-profile}"
            if [ -z ''${QEMU_EXTRA_KERNEL_CMDLINE+x} ]; then
              declare -r full_cmd="$cmd"
            else
              declare -r full_cmd="$cmd $QEMU_EXTRA_KERNEL_CMDLINE"
            fi
            exec -a qemu-system-riscv64 \
              ${qemu}/bin/qemu-system-riscv64 -nographic \
              -machine virt -m "$mem" -append "$full_cmd" \
              -kernel ${bbl}/bin/bbl \
              -initrd ${initrd}/initrd -device virtio-scsi-device \
              -device scsi-hd,drive=hd0 \
              -drive file="$image",id=hd0 "$@"
          '';
      };
in self
