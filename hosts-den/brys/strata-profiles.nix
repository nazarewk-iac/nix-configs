# The Strata profiles llama-swap can switch between.
#
# Strata is not llama-server, so it cannot use the generated `cmd`. The llm aspect accepts a
# complete `command` for exactly this case, and `strata-serve` is the foreground adaptor: it
# materialises one profile config and execs `strata serve` on the port llama-swap passes.
#
# The three profiles and their measured numbers are in
# docs/tasks/2026-11/brys-r9700-model-fit/measurements.md.
{ lib, pkgs, ... }:
{
  # llama-swap starts its models inside its own systemd sandbox, where bubblewrap cannot create a
  # user namespace, so the FHS wrapper is unusable for a model command. nix-ld runs the Terminal's
  # bundled CPython in place instead, which needs no namespace at all.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
      zlib
      libxcrypt
    ];
  };

  # The Strata profiles must write settings, logs and their runtime state into the model dataset,
  # and llama-swap's unit sandboxes that path read-only. This grants exactly that one directory.
  # Strata refuses files that another user owns ("not allowed to open one of its own files"), and
  # a DynamicUser has a random UID. A fixed service user is the smallest change that lets llama-swap
  # spawn the Strata profiles at all; the dataset below is already kdn-owned.
  systemd.services.llama-swap.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "kdn";
    Group = "users";
    ReadWritePaths = [ "/var/lib/kdn/llms/models/.bench" ];
  };

  environment.systemPackages = [
    # The FHS wrapper from `nix build .#strata`, so `strata serve` starts on NixOS.
    pkgs.kdn.strata
    # llama-swap runs its `cmd` with a fixed PATH that holds neither `python3` nor the system
    # profile, so the wrapper pins both instead of trusting the caller's environment.
    (pkgs.writeShellScriptBin "strata-serve" ''
      export PATH=${pkgs.lib.makeBinPath [ pkgs.python3 pkgs.coreutils ]}:$PATH
      exec ${pkgs.bash}/bin/bash ${./strata-serve.sh} "$@"
    '')
  ];
}
