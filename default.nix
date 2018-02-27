{ nixpkgs ? <nixpkgs> # TODO peg revision once stable
, imageSize ? "200G"
}:
let lib = import (nixpkgs + "/lib");
    crossSystem = lib.systems.examples.riscv64;
    crossPkgs = import nixpkgs { inherit crossSystem; };
    pkgs = import nixpkgs {};
    closureInfo = pkgs.callPackage ./closure-info.nix {};
    kernel = crossPkgs.linux_riscv;
    initrd-modules = (pkgs.makeModulesClosure
      { inherit kernel;
        firmware = null;
        rootModules = [ "virtio_scsi" "virtio_mmio" "sd_mod"
                        "crc32c" "btrfs"
                      ];
      }).overrideAttrs (orig:
        { builder = (pkgs.writeShellScriptBin "modules-builder.sh"
            ''
              source ${orig.builder}
              xargs unxz < $out/insmod-list
              sed -i 's/\.xz$//' $out/insmod-list
            '') + "/bin/modules-builder.sh";
        });
    init = crossPkgs.stdenv.mkDerivation
      { name = "init";
        buildInputs = [ crossPkgs.stdenv.cc.libc.static ];
        nativeBuildInputs = [ crossPkgs.removeReferencesTo ];
        unpackPhase = "true";
        buildPhase =
          "${crossPkgs.stdenv.cc.targetPrefix}cc ${./init.c} -O3 " +
          "-o init -static";
        installPhase =
          "mkdir -p $out/bin && install -m755 init $out/bin";
        postFixup =
          "remove-references-to -t ${crossPkgs.stdenv.cc.libc} " +
          "$out/bin/init";
      };
    initrd = pkgs.makeInitrd
      { contents =
          [ { object = "${init}/bin/init";
              symlink = "/init";
            }
            { object = "${initrd-modules}/insmod-list";
              symlink = "/insmod-list";
            }
          ];
        compressor = "xz -9 --check=crc32";
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
                                      "busybox"
                                    ] ++ [ kernel ];
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
            mkfs.btrfs --label root /dev/vda1
            mkdir /mnt
            mount /dev/vda1 /mnt

            nix-store --load-db <${image-closure}/registration
            nix-store -r ${base-profile} --option store /mnt \
              --option substituters "/?trusted=true"

            mkdir -p -m755 /mnt/nix/var/nix/profiles
            ln -s ${base-profile} /mnt/nix/var/nix/profiles/system-1-link
            ln -s system-1-link /mnt/nix/var/nix/profiles/system

            mkdir -p /mnt/dev

            # Sigh
            mkdir -p /mnt/bin
            ln -s ${base-profile}/bin/sh /mnt/bin

            touch /mnt/needs-resize
            umount /mnt
          '');
    self =
      { make-image = pkgs.writeShellScriptBin "make-image"
          ''
            declare -r file="''${2-nix-store-image.qcow2}"
            declare -r size="''${1-${imageSize}}"
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
              ${self.make-image}/bin/make-image ${imageSize} "$image"
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
