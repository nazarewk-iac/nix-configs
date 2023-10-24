{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.k8s;
in
{
  options.kdn.development.k8s = {
    enable = lib.mkEnableOption "k8s development";

    patchedKubectl.enable = lib.mkEnableOption "patched kubectl";
    # https://github.com/kubernetes/kubernetes/pull/109361
    patchedKubectl.commit = lib.mkOption {
      readOnly = true;
      default = "b3aa60fae23aa4a27ca28d6564157150f2c397c1";
    };
    patchedKubectl.checksum = lib.mkOption {
      readOnly = true;
      default = "sha256-UNbohbzdMShE2CJ+CRF0DV7I4JviVMOIYDkUQZ0t/TM=";
    };
  };


  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.development.data.enable = true;

      environment.interactiveShellInit = ''
        export KREW_ROOT="$HOME/.cache/krew"
        export PATH="$PATH:$KREW_ROOT/bin"
      '';
      environment.shellAliases = {
        "kc" = "${pkgs.kubecolor}/bin/kubecolor";
      };
      programs.fish.interactiveShellInit = ''
        complete -c kc --wraps kubectl
        complete -c kubecolor --wraps kubectl
      '';
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
        (wrapHelm kubernetes-helm {
          plugins = with pkgs.kubernetes-helmPlugins; [
            helm-diff
            helm-git
          ];
        })
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

        # Argo
        argo # workflows
        argocd # CD
        vault
      ];
    })
    (lib.mkIf cfg.patchedKubectl.enable {
      nixpkgs.overlays = [
        (final: prev: {
          kubectl = prev.kubectl.overrideAttrs (old:
            {
              version = "1.24.x-${cfg.patchedKubectl.commit}";

              src = prev.fetchFromGitHub {
                owner = "nazarewk";
                repo = "kubernetes";
                rev = cfg.patchedKubectl.commit;
                sha256 = cfg.patchedKubectl.checksum;
              };
            });
        })
      ];
    })
  ];
}
