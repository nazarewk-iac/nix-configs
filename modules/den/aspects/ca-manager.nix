# The `ca-manager` aspect. It puts the `kdn-certs` CLI and the CA DAG into a devenv shell, and it
# owns the smallstep server lifecycle.
#
# ## What it emits
#
# The aspect includes `kdn.ca-dag`, so the shell carries the CA graph option set. It adds the
# `kdn-certs` package to `config.packages`. It adds no service, no system trust and no file.
#
# ## Why it is separate from `kdn.ca`
#
# `kdn.ca` trusts a CA as a system CA. It has the `nixos` class. It mounts `/etc/kdn/ca/<name>.pub`
# and adds each file to `security.pki.certificateFiles`. It never generates a key and never signs a
# certificate.
#
# `kdn.ca-manager` runs in a devenv shell. It holds no system trust. It owns the sign lifecycle. The
# two aspects therefore have different classes, different jobs and different option trees. The new
# tree uses the name `kdn.ca-manager`, so the two trees cannot clash.
#
# ## Why it is separate from `kdn.ca-dag`
#
# `kdn.ca-dag` declares the option set only. It emits no configuration and it starts no process. It
# is available in four classes: `nixos`, `darwin`, `homeManager` and `devenv`.
#
# A host that consumes certificates needs the DAG data, not the CLI. So the data layer stays inert.
# The separation gives three results:
#
#   - An empty `kdn.ca-dag.cas` is a true no-op, as `checks/standalone.nix` requires.
#   - A consumer that reads the DAG pays no package build.
#   - `kdn.ca-manager` stays devenv-only, while `kdn.ca-dag` stays in four classes.
#
# ## The package comes in by a relative path literal
#
# A relative path literal needs no overlay and no `pkgs.kdn.*` entry. It also keeps the evaluation
# on one file. ./ssh-access.nix uses the same shape.
#
# ## The smallstep lifecycle
#
# The CLI shells out to `step` and `step-ca`. `step-ca` runs only while one sign operation needs it.
# The lifecycle has five steps: start a transient `step-ca`, decrypt the CA key (prompt for the
# YubiKey touch when the key needs it), sign, terminate, and clean the temporary `ca.json` and the
# PID file. `step certificate create --ca … --ca-key …` and `step ca certificate --offline` both
# work with no network, so the lifecycle needs no listening port and no long-lived daemon.
#
# The lifecycle itself lives in the CLI (`internal/smallstep`). This aspect only ships the CLI and
# the DAG into the shell.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. An empty CA DAG is the no-op.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.ca-manager.includes = [ kdn.ca-dag ];

  kdn.ca-manager.devenv =
    { pkgs, ... }:
    {
      packages = [ (pkgs.callPackage ../../../packages/kdn-certs { }) ];

      # The aspect's own smoke test. It travels with the aspect, so an adopter gets it too.
      #
      # devenv puts this in `config.enterTest`, and `config.test` wraps it as a script. It runs
      # under `devenv test` and under `checks.<system>.den-smoke-*`. It does **not** run on shell
      # entry (`enterShell`), and it never runs during a nix-darwin or a NixOS activation.
      #
      # Every assertion stays offline. The build sandbox has no network, no real `$HOME` and no CA.
      # `--help` reads no flake and opens no connection.
      enterTest = ''
        echo "• ca-manager: the CLI prints its command table" >&2
        kdn-certs --help | grep -q 'plan'

        echo "• ca-manager: the CLI exits 0 on --help" >&2
        kdn-certs --help >/dev/null
      '';
    };
}
