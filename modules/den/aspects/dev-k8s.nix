# The `development/k8s` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the Kubernetes command-line set: `kubectl`, `kustomize`, `k9s`, Helm with two
# plugins, the Argo tools, and two small wrapper scripts. A NixOS host also gets the `krew` path
# and the `kc` alias.
#
# ## One declaration, three classes
#
# The one option lives in the `declaration` module below, and each target imports it. Only one
# class loads per evaluation, so the module system sees exactly one declaration each time.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **The old `kdn.development.data.enable` write becomes an `includes` entry.** den collapses the
#    diamond, so several aspects may name `dev-data` and it loads once.
# 4. **The Lens install becomes an option.** The old module reads `kdn.desktop.enable`. den has no
#    `enable` option at all, so `kdn.dev-k8s.lens.install` defaults to the shared switch
#    `kdn.graphical` of ../common/graphical.nix. A consumer also sets the option directly.
# 5. **`lib.mkIf` leaves the package list.** `filter-packages.nix` forces `outPath` on every
#    element, and an unresolved `mkIf` attribute set has none. `lib.optional` gives the same result
#    and it resolves at once.
# 6. **The wrapper script reads ./dev-k8s/kubectl-eks_config.sh.** The old file keeps its place;
#    this is a copy, because an aspect must not read the old tree.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `lens.install` is the name for change 4.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  declaration =
    { config, lib, ... }:
    {
      imports = [ ../common/graphical.nix ];

      options.kdn.dev-k8s.lens.install = lib.mkOption {
        type = lib.types.bool;
        default = config.kdn.graphical;
        defaultText = lib.literalExpression "config.kdn.graphical";
        example = true;
        description = ''
          Install Lens, the Kubernetes IDE.

          The old module reads `kdn.desktop.enable` for this. A den aspect declares no `enable`
          option, so the default follows the shared switch `kdn.graphical`, from
          ../common/graphical.nix. A consumer that sets this option directly still wins, because a
          plain value beats a default.
        '';
      };
    };

  # Every package this aspect ships, in every class. One list, three writers.
  packagesOf =
    {
      config,
      lib,
      pkgs,
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    filterPackages (
      # kubernetes IDE
      lib.optional config.kdn.dev-k8s.lens.install pkgs.lens
      ++ (with pkgs; [
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
          text = builtins.readFile ./dev-k8s/kubectl-eks_config.sh;
        })

        # Argo
        argo-workflows
        argocd # CD
      ])
    );

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      environment.systemPackages = packagesOf { inherit config lib pkgs; };

      environment.interactiveShellInit = ''
        export KREW_ROOT="$HOME/.cache/krew"
      '';
      environment.shellAliases = {
        "kc" = "${pkgs.kubecolor}/bin/kubecolor";
      };
      programs.fish.interactiveShellInit = ''
        fish_add_path --append --move "$KREW_ROOT/bin"
        complete -c kc --wraps kubectl
        complete -c kubecolor --wraps kubectl
      '';
    };

  darwinTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      environment.systemPackages = packagesOf { inherit config lib pkgs; };
    };

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      home.packages = packagesOf { inherit config lib pkgs; };
    };
in
{
  kdn.dev-k8s.includes = [ kdn.dev-data ];

  kdn.dev-k8s.nixos = nixosTarget;
  kdn.dev-k8s.darwin = darwinTarget;
  kdn.dev-k8s.homeManager = homeTarget;
}
