{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.k8s;
in {
  options.nazarewk.development.k8s = {
    enable = mkEnableOption "k8s development";
  };


  config = mkIf cfg.enable {
    nazarewk.development.data.enable = true;

    environment.interactiveShellInit = ''
      export KREW_ROOT="$HOME/.cache/krew"
      export PATH="$PATH:$KREW_ROOT/bin"
    '';

    environment.systemPackages = with pkgs; [
      lens # kubernetes IDE
      # kubernetes
      kubectl # dep for: chart-testing
      kustomize
      k9s
      kubectx
      krew

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
        runtimeInputs = with pkgs; [ awscli2 kubectl coreutils gawk ];
        text = ''
          cluster_name="$1"
          profile="''${2:-"$AWS_PROFILE"}"
          alias="''${3:-"$cluster_name"}"
          set -x
          aws eks update-kubeconfig --profile="$profile" --name="$cluster_name" --alias="$alias"
          # set ARN-based context
          # shellcheck disable=SC2046
          kubectl config set-context $(kubectl config get-contexts "$cluster_name" | tail -n1 | awk '{ print $3 " --cluster=" $3 " --user=" $4 }')
        '';
      })
    ];
  };
}