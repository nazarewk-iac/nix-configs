{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.k8s;
in
{
  options.nazarewk.development.k8s = {
    enable = mkEnableOption "k8s development";
  };


  config = mkIf cfg.enable {
    nazarewk.development.data.enable = true;

    nixpkgs.overlays = [
      (final: prev: {
        kubectl = prev.kubectl.overrideAttrs (old:
          let commit = "955596ad054e442125c8353b6df8951fdc91a0f3"; in
          {
            version = "1.24.0-${commit}";

            src = prev.fetchFromGitHub {
              owner = "nazarewk";
              repo = "kubernetes";
              rev = commit;
              sha256 = "sha256-jKYiGSRQpuPyjQZVEIoLqIgo4fqQWkRDeImcsCMNkio=";
            };
          });
      })
    ];

    environment.interactiveShellInit = ''
      export KREW_ROOT="$HOME/.cache/krew"
      export PATH="$PATH:$KREW_ROOT/bin"
    '';
    environment.shellAliases = {
      "kc" = "${pkgs.kubecolor}/bin/kubecolor";
    };
    environment.systemPackages = with pkgs; [
      lens # kubernetes IDE
      # kubernetes
      kubectl # dep for: chart-testing
      kustomize
      k9s
      kubectx
      krew
      kubectl-tree
      kubecolor
      kubectl-doctor

      istioctl

      # see https://olm.operatorframework.io/docs/getting-started/
      operator-sdk

      cmctl # cert-manager CLI

      # Helm
      kubernetes-helm # dep for: chart-testing
      chart-testing
      helmsman

      yamale # dep for: chart-testing
      yamllint # dep for: chart-testing

      (pkgs.writeShellApplication {
        name = "kubectl-krew";
        runtimeInputs = with pkgs; [ krew ];
        text = ''
          krew "$@"
        '';
      })
      #      (pkgs.writeShellApplication {
      #        name = "kubectl-get_all";
      #        runtimeInputs = with pkgs; [ kubectl coreutils gnugrep util-linux ];
      #        text = ''
      #          [ -z "''${DEBUG:-}" ] || set -x
      #          resources_extra=()
      #          grep -E -- '( |^)((-n [a-z-]+)|(--namespace( |=)[a-z-]+)|(--namespaced))( |$)' <<<"$*" >/dev/null && resources_extra+=(--namespaced)
      #          # https://github.com/koalaman/shellcheck/wiki/SC2207
      #          mapfile -t resources < <(kubectl api-resources --verbs=list "''${resources_extra[@]}" -o name)
      #          kubectl get "$( tr ' ' ',' <<<"''${resources[*]}" )" "$@"
      #        '';
      #      })

      (pkgs.writeShellApplication {
        name = "kubectl-eks_config";
        runtimeInputs = with pkgs; [ awscli2 kubectl coreutils gawk yq gnused ];
        text = builtins.readFile ./kubectl-eks_config.sh;
      })
    ];
  };
}
