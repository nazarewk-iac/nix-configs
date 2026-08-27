# OpenSSH ssh-agent home-manager slot.
#
# Runs the upstream OpenSSH `ssh-agent` as the user SSH agent, in place of the macOS built-in
# agent. The built-in macOS agent does not support FIDO2 security-key keys (`sk-ssh-ed25519`).
# The nixpkgs `openssh` build links `libfido2`, so it supports YubiKey resident keys.
#
# This slot targets `home` (home-manager, all users through `sharedModules`). It enables the
# upstream home-manager `services.ssh-agent` module. That module supports macOS through a launchd
# agent, and it sets `SSH_AUTH_SOCK` for the user shells (bash, fish, nushell). On Linux the same
# module uses a systemd user service.
#
# On macOS the slot also fully eliminates the built-in agent for the user, so every process
# (GUI apps included) uses OpenSSH. A login agent `ssh-agent-claim`:
#   1. points the whole launchd domain `SSH_AUTH_SOCK` at the OpenSSH socket (`launchctl setenv`),
#   2. stops and permanently disables the built-in `com.openssh.ssh-agent` for the user.
# A user can disable its own `gui/<uid>` agent without root; the disable persists across reboots
# through `/var/db/com.apple.xpc.launchd/disabled.<uid>.plist`.
{
  lib,
  config,
  ...
}:
let
  cfg = config.kdn.home.ssh-agent;
in
{
  options.kdn.home.ssh-agent = {
    enable = lib.mkEnableOption "OpenSSH ssh-agent as the user SSH agent (FIDO2/security-key capable)";
  };

  config = lib.mkIf cfg.enable {
    home =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      # Skip root. Root has no GUI login session, so the launchd `gui/0` bootstrap
      # fails with error 125. The `home` slot applies to all home-manager users.
      lib.mkIf (config.home.username != "root") (
        lib.mkMerge [
          {
            services.ssh-agent.enable = true;
            # Use the nixpkgs OpenSSH build. It links libfido2, so ssh-agent signs with
            # `sk-ssh-ed25519` YubiKey keys.
            services.ssh-agent.package = pkgs.openssh;
          }
          (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
            let
              # The same socket path the home-manager ssh-agent module binds and exports.
              socket = "$(${lib.getExe pkgs.getconf} DARWIN_USER_TEMP_DIR)/ssh-agent";
              claim = pkgs.writeShellScript "ssh-agent-claim" ''
                set -u
                uid="$(id -u)"
                # Point the whole launchd domain (GUI apps included) at the OpenSSH agent.
                /bin/launchctl setenv SSH_AUTH_SOCK "${socket}"
                # Stop and permanently disable the macOS built-in ssh-agent for the user.
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
  };
}
