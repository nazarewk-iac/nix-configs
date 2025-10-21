{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.development.k8s;
in
{
  options.kdn.development.k8s = {
    enable = lib.mkEnableOption "k8s development";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.development.data.enable = true;

      environment.interactiveShellInit = ''
        export KREW_ROOT="$HOME/.cache/krew"
        fish_add_path --append --move "$KREW_ROOT/bin"
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
          runtimeInputs = with pkgs; [
            awscli2
            kubectl
            coreutils
            gawk
            yq
            gnused
          ];
          text = builtins.readFile ./kubectl-eks_config.sh;
        })

        # Argo
        argo # workflows
        argocd # CD
        # vault # TODO: 2024-02-13: builds for a VERY long time on the laptop
      ];
    })
  ];
}
