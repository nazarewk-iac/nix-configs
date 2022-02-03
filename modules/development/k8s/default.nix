{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # kubernetes
    kubectl # dep for: chart-testing
    k9s
    kubectx

    # Helm
    kubernetes-helm # dep for: chart-testing
    chart-testing
    helmsman

    yamale # dep for: chart-testing
    yamllint # dep for: chart-testing

    (pkgs.writeShellApplication {
      name = "kubectl-get_all";
      runtimeInputs = with pkgs; [ kubectl coreutils gnugrep util-linux ];
      text = ''
        [ -z "''${DEBUG:-}" ] || set -x
        resources_extra=()
        grep -E -- '( |^)(-n|--namespace( )|--namespaced( |$))' <<<"$*" >/dev/null && extra+=(--namespaced)
        # https://github.com/koalaman/shellcheck/wiki/SC2207
        mapfile -t resources < <(kubectl api-resources --verbs=list "''${resources_extra[@]}" -o name)
        kubectl get "$( tr ' ' ',' <<<"''${resources[*]}" )" "$@"
      '';
    })
  ];
}