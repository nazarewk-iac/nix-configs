# The `ssh-agent` slot, as a den aspect. It ports `modules/slots/ssh-agent/default.nix`.
#
# The slot stays in place and keeps working. This file is the parallel den implementation.
#
# ## Why this slot is next
#
# It is the **first aspect with one target only, and that target is `homeManager`**. Every aspect
# before it carried a host-class half. So it tests the user scope alone: a den host must include it
# through a **user**, never through the host aspect. den partitions an aspect by scope, and a
# host-scope `homeManager` half never reaches `home-manager.users.<name>`.
#
# ## What it does
#
# It runs the OpenSSH `ssh-agent` as the user agent, in place of the macOS built-in agent. The
# built-in agent supports no FIDO2 security-key key (`sk-ssh-ed25519`). The nixpkgs `openssh` build
# links `libfido2`, so it signs with a YubiKey resident key.
#
# On macOS the aspect also removes the built-in agent for the user. A login agent
# `ssh-agent-claim`:
#   1. points the whole launchd domain `SSH_AUTH_SOCK` at the OpenSSH socket (`launchctl setenv`),
#   2. stops and permanently disables the built-in `com.openssh.ssh-agent` for the user.
# A user disables its own `gui/<uid>` agent with no root. The disable survives a reboot through
# `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** A target module below takes `config`, `lib` and `pkgs` only —
#    the arguments every NixOS, nix-darwin, home-manager and devenv evaluation already gives. An
#    argument such as `inputs` or `kdnConfig` would force the consumer to pass `specialArgs`, and
#    that machinery is the whole reason this tree exists. Capture such a value in **this file's**
#    own arguments instead, and close over it.
{ ... }:
{
  kdn.ssh-agent.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    # Skip root. Root has no GUI login session, so the launchd `gui/0` bootstrap fails with error
    # 125. A den aspect reaches one user at a time, unlike the slot's `sharedModules`, so this
    # guard is a safety net and not the main mechanism.
    lib.mkIf (config.home.username != "root") (
      lib.mkMerge [
        {
          services.ssh-agent.enable = true;
          # Use the nixpkgs OpenSSH build. It links libfido2, so the agent signs with an
          # `sk-ssh-ed25519` YubiKey key.
          services.ssh-agent.package = pkgs.openssh;
        }
        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
          let
            # The same socket path that the home-manager ssh-agent module binds and exports.
            socket = "$(${lib.getExe pkgs.getconf} DARWIN_USER_TEMP_DIR)/ssh-agent";
            claim = pkgs.writeShellScript "ssh-agent-claim" ''
              set -u
              uid="$(id -u)"
              # Point the whole launchd domain (GUI applications included) at the OpenSSH agent.
              /bin/launchctl setenv SSH_AUTH_SOCK "${socket}"
              # Stop and permanently disable the macOS built-in ssh-agent for this user.
              /bin/launchctl bootout "gui/$uid/com.openssh.ssh-agent" 2>/dev/null || true
              /bin/launchctl disable "gui/$uid/com.openssh.ssh-agent" || true
            '';
          in
          {
            launchd.agents.ssh-agent-claim = {
              enable = true;
              config = {
                ProgramArguments = [ "${claim}" ];
                RunAtLoad = true;
              };
            };
          }
        ))
      ]
    );
}
