# Tier-1 assertions for the two `virt-microvm-*` aspects.
#
# Every assertion is `{ name; expected; actual; }`, and `mkEvalCheck` compares the two at evaluation
# time. Nothing here starts a virtual machine.
#
# ## The subjects
#
# | Subject | Class | What it states |
# |---|---|---|
# | `nixosHost` | `nixos` | the microvm host aspect, with no guest declared |
# | `nixosGuest` | `nixos` | the microvm guest aspect |
#
# Both aspects emit a `nixos` target and nothing else, so there is no `darwin` and no `homeManager`
# subject.
#
# ## Why the host subject declares no guest
#
# A real guest is a whole second NixOS evaluation, and the tmpfiles rule is the only thing that reads
# one. So the host subject states the empty case: the rule list holds no guest directory, and the
# state directory still reaches the persist set. A guest evaluation belongs to a tier-2 check, not
# here.
{
  lib,
  denLib,
  harness,
  ...
}:
let
  inherit (harness) bareNixos;

  sorted = lib.sort (a: b: a < b);
  has = name: packages: lib.elem name (map lib.getName packages);

  virtNames = [
    "virt-microvm-guest"
    "virt-microvm-host"
  ];

  nixosHostSystem = bareNixos (
    denLib.imports {
      class = "nixos";
      aspects = [ "virt-microvm-host" ];
    }
  );
  nixosHost = nixosHostSystem.config;

  nixosGuestSystem = bareNixos (
    denLib.imports {
      class = "nixos";
      aspects = [ "virt-microvm-guest" ];
    }
    ++ [ { networking.hostName = "den-guest"; } ]
  );
  nixosGuest = nixosGuestSystem.config;

  assertions = [
    # ---------------------------------------------------------------- instantiation
    {
      name = "both microvm aspects instantiate in the nixos class";
      expected = {
        host = true;
        guest = true;
      };
      actual = {
        host = builtins.isString nixosHostSystem.config.system.build.toplevel.drvPath;
        guest = builtins.isString nixosGuestSystem.config.system.build.toplevel.drvPath;
      };
    }
    {
      name = "each microvm aspect emits the classes its old module had";
      expected = {
        virt-microvm-guest = [ "nixos" ];
        virt-microvm-host = [ "nixos" ];
      };
      actual = lib.mapAttrs (_: sorted) (lib.getAttrs virtNames denLib.pairs);
    }

    # ---------------------------------------------------------------- virt-microvm-host
    {
      name = "the host aspect turns the host role on, with no false branch left";
      expected = true;
      actual = nixosHost.microvm.host.enable;
    }
    {
      name = "the host aspect registers the microvm flake and trusts its cache";
      expected = {
        registry = true;
        key = true;
      };
      actual = {
        registry = nixosHost.nix.registry ? microvm;
        key = lib.elem "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys=" nixosHost.nix.settings.trusted-public-keys;
      };
    }
    {
      name = "the host aspect installs the microvm command";
      expected = true;
      actual = has "microvm" nixosHost.environment.systemPackages;
    }
    {
      name = "the host aspect keeps the state directory across a reboot";
      expected = [ "/var/lib/microvms" ];
      actual = nixosHost.kdn.disks.persist."usr/data".directories;
    }
    {
      name = "no guest directory rule appears while the host declares no guest";
      expected = {
        vms = [ ];
        rules = [ ];
      };
      actual = {
        vms = builtins.attrNames nixosHost.microvm.vms;
        rules = lib.filter (
          rule: lib.hasInfix "/var/lib/microvms-persist/" rule
        ) nixosHost.systemd.tmpfiles.rules;
      };
    }

    # ---------------------------------------------------------------- virt-microvm-guest
    {
      name = "the guest aspect turns the guest role on and drops the sudo password";
      expected = {
        guest = true;
        sudo = false;
      };
      actual = {
        guest = nixosGuest.microvm.guest.enable;
        sudo = nixosGuest.security.sudo.wheelNeedsPassword;
      };
    }
    {
      name = "the guest keeps the journal, the machine id and the two host keys";
      expected = {
        path = "/nix/persist/microvm";
        directories = [ "/var/log/journal" ];
        files = [
          "/etc/machine-id"
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_rsa_key"
        ];
        symlinks = [
          "symlink"
          "symlink"
          "symlink"
        ];
      };
      actual =
        let
          bucket = nixosGuest.preservation.preserveAt."microvm";
        in
        {
          path = bucket.persistentStoragePath;
          directories = map (d: d.directory) bucket.directories;
          files = map (f: f.file) bucket.files;
          symlinks = map (f: f.how) bucket.files;
        };
    }
    {
      name = "the guest shares the read-only store and one share per preservation bucket";
      expected = [
        {
          mountPoint = "/nix/.ro-store";
          proto = "virtiofs";
          source = "/nix/store";
          tag = "ro-store";
        }
        {
          mountPoint = "/nix/persist/microvm";
          proto = "virtiofs";
          source = "/var/lib/microvms-persist/den-guest/microvm";
          tag = "microvm-persist-microvm";
        }
      ];
      actual = map (share: {
        inherit (share)
          mountPoint
          proto
          source
          tag
          ;
      }) nixosGuest.microvm.shares;
    }
    {
      name = "the guest share source follows the machine name";
      expected = "/var/lib/microvms-persist/den-renamed/microvm";
      actual =
        let
          renamed =
            (bareNixos (
              denLib.imports {
                class = "nixos";
                aspects = [ "virt-microvm-guest" ];
              }
              ++ [ { networking.hostName = "den-renamed"; } ]
            )).config;
        in
        (lib.findFirst (share: share.tag == "microvm-persist-microvm") {
          source = null;
        } renamed.microvm.shares).source;
    }
  ];

  # ------------------------------------------------------------------ the coverage rows
  instantiatedBy = {
    virt-microvm-guest = "den-eval-virtualisation (bare nixos, the guest subject)";
    virt-microvm-host = "den-eval-virtualisation (bare nixos, the host subject)";
  };
in
{
  inherit assertions instantiatedBy;
}
