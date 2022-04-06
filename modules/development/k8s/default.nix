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

      istioctl

      # see https://olm.operatorframework.io/docs/getting-started/
      operator-sdk

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
        runtimeInputs = with pkgs; [ awscli2 kubectl coreutils gawk yq ];
        text = ''
          export cluster_name="$1"
          export AWS_PROFILE="''${2:-"$AWS_PROFILE"}"
          alias="''${3:-"$cluster_name"}"

          set -x
          aws eks update-kubeconfig --profile="$AWS_PROFILE" --name="$cluster_name" --alias="$alias"

          cluster_arn="$(kubectl config view --minify | yq -r '.clusters[].name')"
          user="$(kubectl config view --minify | yq -r '.users[].name')"

          kubectl config set-context "$cluster_arn" --cluster="$cluster_arn" --user="$user"

          readarray -t args < <(jq -rn 'env | to_entries[] | select(.key | startswith("AWS_")) | "--exec-env=\(.key)=\(.value)"')
          kubectl config set-credentials "$user" "''${args[@]}"
        '';
      })
    ];
  };
}