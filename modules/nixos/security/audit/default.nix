{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.security.audit;
  tomlFormat = pkgs.formats.toml {};
in {
  options.kdn.security.audit = {
    enable = lib.mkEnableOption "Linux audit setup";

    auditd.startOnDemand = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };

    auditd.config = lib.mkOption {
      type = with lib.types; attrsOf str;
      default = {};
    };

    laurel.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    laurel.config = lib.mkOption {
      type = tomlFormat.type;
    };
    laurel.package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.laurel;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      security.audit.enable = true;
      security.auditd.enable = true;
    }
    {
      environment.etc."audit/auditd.conf".text = lib.trivial.pipe cfg.auditd.config [
        (lib.attrsets.mapAttrsToList (key: value: ''${key} = ${value}''))
        (builtins.concatStringsSep "\n")
      ];
      kdn.security.audit.auditd.config = builtins.mapAttrs (_: lib.mkDefault) {
        space_left = "10%";
        space_left_action = "rotate";
        admin_space_left = "5%";
        admin_space_left_action = "rotate";
      };
    }
    {
      systemd.services.auditd.wantedBy = lib.mkIf cfg.auditd.startOnDemand (lib.mkForce []);
    }
    {
      systemd.services.auditd.serviceConfig.ExecStart = let
        pkg = pkgs.audit.overrideAttrs (old: {
          patches =
            old.patches
            or []
            ++ [
              (pkgs.fetchpatch2 {
                # see https://github.com/linux-audit/audit-userspace/pull/433
                url = "https://github.com/linux-audit/audit-userspace/commit/75a314d99c92456e43c60fa0bb50ae16e0444207.patch?full_index=1'";
                sha256 = "sha256-5dIcyt1agVJ06hodi8Z88U+cEjTR27vlFxMwWkyUf/c=";
              })
            ];
        });
      in
        lib.mkForce "${pkg}/bin/auditd -l -n -s nochange";
    }
    (lib.mkIf cfg.laurel.enable {
      users.groups.laurel = {};
      users.users.laurel = {
        isSystemUser = true;
        description = "Laurel audit user";
        group = "laurel";
        shell = "${pkgs.shadow}/bin/nologin";
        home = "/var/log/laurel";
        homeMode = "0750";
      };
      kdn.security.audit.auditd.config = builtins.mapAttrs (_: lib.mkDefault) {
        write_logs = "no"; # this does not seem to work
        num_logs = "1";
        max_log_file = "10";
        max_log_file_action = "rotate";
      };
      environment.etc."audit/plugins.d/laurel.conf".text = ''
        active = yes
        direction = out
        type = always
        format = string
        path = ${cfg.laurel.package}/bin/laurel
        args = --config /etc/laurel/config.toml
      '';
      environment.etc."laurel/config.toml".source = tomlFormat.generate "laurel-config.toml" cfg.laurel.config;
      systemd.user.tmpfiles.rules = [
        "d /var/log/laurel 0750 laurel laurel -"
      ];
    })
    (lib.mkIf cfg.laurel.enable {
      # track all processes for laurel
      # https://github.com/threathunters-io/laurel/blob/b655fe44ee63ff52c3f811c01bca4562dc2a61d0/man/laurel-audit-rules.7.md#log-all-fork-and-exec-calls-for-reliable-process-tracking
      security.audit.rules = [
        ## Ignore clone( flags=CLONE_VM|… ), log other process-creating calls
        "-a never,exit  -F arch=b32 -S clone -F a2&0x100"
        "-a never,exit  -F arch=b64 -S clone -F a2&0x100"
        "-a always,exit -F arch=b32 -S fork,vfork,clone,clone3 -k fork"
        "-a always,exit -F arch=b64 -S fork,vfork,clone,clone3 -k fork"
        "-a always,exit -F arch=b32 -S execve,execveat"
        "-a always,exit -F arch=b64 -S execve,execveat"
      ];
      kdn.security.audit.laurel.config = {
        filter = {
          filter-keys = ["fork"];
          filter-action = "drop";
          keep-first-per-process = true;
        };
      };
    })
    {
      kdn.security.audit.laurel.config = let
        MiB = 1024 * 1024;
        min = 60;
      in {
        # see https://github.com/threathunters-io/laurel/blob/b655fe44ee63ff52c3f811c01bca4562dc2a61d0/man/laurel.8.md#configuration
        user = "laurel";
        directory = lib.mkDefault "/var/log/laurel";
        statusreport-period = 10 * min;
        marker = lib.mkDefault "KDN-LAUREL-STARTED";
        auditlog = {
          file = lib.mkDefault "audit.log";
          size = lib.mkDefault (100 * MiB);
          generations = lib.mkDefault 10;
        };
        filterlog = {
          file = lib.mkDefault "filtered.log";
          size = lib.mkDefault (10 * MiB);
          generations = lib.mkDefault 10;
        };
        transform = {
          execve-argv = lib.mkDefault ["array"];
          execve-argv-limit-bytes = lib.mkDefault (3 * MiB);
        };
        translate = {
          userdb = lib.mkDefault true;
          universal = lib.mkDefault true;
          drop-raw = lib.mkDefault false;
        };
        enrich = {
          execve-env = [
            "LD_PRELOAD"
            "LD_LIBRARY_PATH"
          ];
          container = lib.mkDefault true;
          systemd = lib.mkDefault true;
          pid = lib.mkDefault true;
          script = lib.mkDefault true;
          user-groups = lib.mkDefault true;
          prefix = lib.mkDefault "enriched_";
        };
        label-process = {
          # https://github.com/threathunters-io/laurel/blob/b655fe44ee63ff52c3f811c01bca4562dc2a61d0/man/laurel.8.md#label-process-section
        };
        filter = {
          # https://github.com/threathunters-io/laurel/blob/b655fe44ee63ff52c3f811c01bca4562dc2a61d0/man/laurel.8.md#filter-section
        };
      };
    }
  ]);
}
