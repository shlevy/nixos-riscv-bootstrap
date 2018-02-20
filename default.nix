{ nixpkgs ? <nixpkgs> # TODO peg revision once stable
}:
let lib = import (nixpkgs + "/lib");
    crossSystem = lib.systems.examples.riscv64;
    crossPkgs = import nixpkgs { inherit crossSystem; };
    pkgs = import nixpkgs {};
    self =
      { # Temporary init until we get systemd up and running.
        init = crossPkgs.stdenv.mkDerivation {
          name = "riscv-init";

          buildInputs = [ crossPkgs.stdenv.cc.libc.static ];

          nativeBuildInputs = [ crossPkgs.removeReferencesTo ];

          unpackPhase = "true";

          buildPhase = ''
            ${crossPkgs.stdenv.cc.targetPrefix}cc -O3 -static \
              ${./init.c} -o init
          '';

          installPhase = ''
            mkdir -p $out/bin
            install -m755 init $out/bin
          '';

          postFixup = ''
            remove-references-to -t ${crossPkgs.stdenv.cc.libc} $out/bin/init
          '';

          allowedReferences = [];
        };
        initrd = pkgs.makeInitrd
          { contents =
              [ { object = "${self.init}/bin/init";
                  symlink = "/init";
                }
                { object = "${self.init}/bin/init";
                  symlink = "/poweroff";
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
