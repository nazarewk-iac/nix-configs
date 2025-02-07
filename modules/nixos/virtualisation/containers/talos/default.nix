{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualisation.containers.talos;
in {
  options.kdn.virtualisation.containers.talos = {
    enable = lib.mkEnableOption "Talos.dev CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.talosctl;
    };

    qemu.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        cfg.package
      ];
    }
    (lib.mkIf cfg.qemu.enable {
      /*
      Requirements from: https://www.talos.dev/v1.5/talos-guides/install/local-platforms/qemu/
      Linux
      a kernel with
          KVM enabled (/dev/kvm must exist) # OK?
          CONFIG_NET_SCH_NETEM enabled  # zcat /proc/config.gz | grep -E 'CONFIG_NET_SCH_(NETEM|INGRESS)'
          CONFIG_NET_SCH_INGRESS enabled
      at least CAP_SYS_ADMIN and CAP_NET_ADMIN capabilities # run as root
      QEMU
      bridge, static and firewall CNI plugins from the standard CNI plugins, and tc-redirect-tap CNI plugin from the awslabs tc-redirect-tap installed to /opt/cni/bin (installed automatically by talosctl)
      iptables
      /var/run/netns directory should exist
      */
      kdn.virtualization.libvirtd.enable = true;
      # verify flags: zcat /proc/config.gz | grep -E 'CONFIG_NET_SCH_(NETEM|INGRESS)'

      virtualisation.containers.containersConf.cniPlugins = with pkgs; [
        # TODO: not needed, could instead wrap symlinked CNIs into `--cni-bin-path` ?
        pkgs.kdn.tc-redirect-tap
      ];

      # TODO: figure out why firewall is preventing Talos from working
      #     controlplane/workers don't get routed to internet, see https://github.com/siderolabs/talos/issues/5548
      networking.firewall.enable = false;

      environment.systemPackages = with pkgs; [
        (pkgs.writeShellApplication {
          name = "talos-qemu-create";
          runtimeInputs = with pkgs; [
            cfg.package
            curl
          ];
          text = ''
            version="''${version:-"${cfg.package.version}"}"
            dir="$XDG_CACHE_HOME/talos/qemu/$version"
            mkdir -p "$dir/_out"
            pushd "$dir"
            for file in  vmlinuz-amd64 initramfs-amd64.xz ; do
              [[ -e "_out/$file" ]] || curl "https://github.com/siderolabs/talos/releases/download/v$version/$file" -L -o "_out/$file"
            done

            sudo --preserve-env=HOME talosctl cluster create \
              --talos-version "v$version" \
              --provisioner qemu \
              --extra-uefi-search-paths=/run/libvirt/nix-ovmf \
              "$@"
          '';
        })
        (pkgs.writeShellApplication {
          name = "talos-qemu-destroy";
          runtimeInputs = with pkgs; [
            cfg.package
          ];
          text = ''
            sudo --preserve-env=HOME talosctl cluster destroy --provisioner qemu "$@"
          '';
        })
      ];
    })
  ]);
}
