# The `development/cloud/aws` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the AWS command-line set: `awscli2`, the Session Manager plugin, `eksctl`, the
# repository's own `aws-sso` helper, and two small scripts.
#
# ## One declaration, three classes
#
# The persist option lives in the `declaration` module below, and each target imports it. Only one
# class loads per evaluation, so the module system sees exactly one declaration each time.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` goes.** Each target writes the native package option of its own class,
#    through ../common/filter-packages.nix. Design B.
# 3. **The persist path becomes a read-only option.** The old module writes
#    `kdn.disks.persist."usr/data".directories`, which another area declares. This aspect publishes
#    `kdn.dev-persist.dev-cloud-aws` and the consumer wires it. See the `apps` aspect for the same
#    pattern.
# 4. **`aws-sso` comes from a plain `callPackage`.** The old module reads the `kdn` package set, so
#    a consumer must add this repository's overlay first. A relative path needs no overlay. The
#    package builds a Python script wrapper, so the call also states the repository root.
# 5. **The two scripts read a copy next to this file.** The old files keep their place; an aspect
#    must not read the old tree.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `lib` and `pkgs` only.
{ ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.dev-persist.dev-cloud-aws = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
        default = {
          "usr/data".directories = [ ".aws" ];
        };
        description = ''
          The paths this aspect keeps across a wipe, in the shape the persist area takes.

          This aspect writes no persist option of its own. A consumer collects every
          `kdn.dev-persist.*` value and wires it in one line.
        '';
      };
    };

  # The root of this repository, as a relative path. `aws-sso` is a Python script package, and it
  # builds its wrapper with `lib.kdn.mkPythonScript` unless a caller states this root.
  repoRoot = ../../..;

  packages =
    pkgs:
    let
      aws-sso = pkgs.callPackage ../../../packages/aws-sso {
        __inputs__.inputs.kdn-configs-src = repoRoot;
      };
    in
    (with pkgs; [
      # AWS
      awscli2
      ssm-session-manager-plugin
      eksctl

      (pkgs.writeShellApplication {
        name = "aws-list-all-parameters";
        runtimeInputs = with pkgs; [
          awscli2
          coreutils
          jq
        ];
        text = builtins.readFile ./dev-cloud-aws/aws-list-all-parameters.sh;
      })
      (pkgs.writeShellApplication {
        name = "argo-eks-token";
        runtimeInputs = with pkgs; [
          awscli2
          jq
        ];
        text = builtins.readFile ./dev-cloud-aws/argo-eks-token.sh;
      })
    ])
    ++ [ aws-sso ];

  filtered = lib: pkgs: import ../common/filter-packages.nix { inherit lib; } (packages pkgs);

  systemTarget =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];

      environment.systemPackages = filtered lib pkgs;
    };

  homeTarget =
    { lib, pkgs, ... }:
    {
      imports = [ declaration ];

      home.packages = filtered lib pkgs;
    };
in
{
  kdn.dev-cloud-aws.nixos = systemTarget;
  kdn.dev-cloud-aws.darwin = systemTarget;
  kdn.dev-cloud-aws.homeManager = homeTarget;
}
