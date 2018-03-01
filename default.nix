{ nixpkgs ? <nixpkgs> # TODO peg revision once stable
, imageSize ? "200G"
}:
let module = { imports =
                 [ ./configuration.nix
                   (nixpkgs + "/nixos/modules/profiles/qemu-guest.nix")
                 ];
             };
    inherit (import (nixpkgs + "/nixos") { configuration = module;
                                         }) system pkgs config;

    nativePkgs = pkgs.buildPackages.buildPackages;
    bbl = pkgs.riscv-pk.override
      { payload = "${config.boot.kernelPackages.kernel}/vmlinux"; };
    qemu = nativePkgs.qemu-riscv;
    closureInfo = nativePkgs.callPackage ./closure-info.nix {};
    image-closure = closureInfo { rootPaths = [ system ]; };
    base-image =
      nativePkgs.vmTools.runInLinuxVM (nativePkgs.runCommand "riscv-base-nix-image"
        { nativeBuildInputs = (map (p: nativePkgs.${p})
            [ "btrfs-progs" "gptfdisk" "nixUnstable" "utillinux" ]);
          preVM = ''
            diskImage=$name.qcow2

            imageSize=$(expr $(cat ${image-closure}/total-nar-size) + 500000000)
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
            nix-store -r ${system} --option store /mnt \
              --option substituters "/?trusted=true"

            mkdir -p -m755 /mnt/nix/var/nix/profiles
            ln -s ${system} /mnt/nix/var/nix/profiles/system-1-link
            ln -s system-1-link /mnt/nix/var/nix/profiles/system

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
            declare -r cmd="console=ttyS0 systemConfig=${system} init=${system}/init loglevel=4"
            if [ -z ''${QEMU_EXTRA_KERNEL_CMDLINE+x} ]; then
              declare -r full_cmd="$cmd"
            else
              declare -r full_cmd="$cmd $QEMU_EXTRA_KERNEL_CMDLINE"
            fi
            exec -a qemu-system-riscv64 \
              ${qemu}/bin/qemu-system-riscv64 -nographic \
              -machine virt -m "$mem" -append "$full_cmd" \
              -kernel ${bbl}/bin/bbl \
              -initrd ${system}/initrd -device virtio-scsi-device \
              -device scsi-hd,drive=hd0 \
              -drive file="$image",id=hd0 \
              -device virtio-net-device,netdev=usernet \
              -netdev user,id=usernet,hostfwd=tcp::10000-:22 "$@"
          '';
      };
in self
