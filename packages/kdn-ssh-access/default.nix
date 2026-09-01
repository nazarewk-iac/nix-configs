{
  lib,
  buildGoModule,
  runCommandLocal,
  makeBinaryWrapper,
  writeText,
  ...
}:
buildGoModule (finalAttrs: {
  pname = "kdn-ssh-access";
  version = "0.0.1";

  src = lib.sourceByRegex ./. [
    ''^go\.(mod|sum)$''
    ''.*\.go$''
  ];

  vendorHash = "sha256-1JM1RHE8hSoHfOOy4eAx+YaKcSFMrBCErkLVk7U7CJU=";

  subPackages = [ "." ];

  # Produce a configured variant: a wrapper with the topology JSON baked in (KDN_SSH_ACCESS_CONFIG),
  # carrying the generated access JSON and ssh drop-in as `passthru.accessConfig` / `.sshConfig`.
  passthru.withConfig =
    configAttrs:
    let
      accessConfig = writeText "kdn-ssh-access.json" (builtins.toJSON configAttrs);
      wrapped =
        runCommandLocal "kdn-ssh-access-configured"
          {
            nativeBuildInputs = [ makeBinaryWrapper ];
            meta.mainProgram = "kdn-ssh-access";
            passthru = { inherit accessConfig sshConfig; };
          }
          ''
            mkdir -p "$out/bin"
            makeWrapper ${lib.getExe finalAttrs.finalPackage} "$out/bin/kdn-ssh-access" \
              --set KDN_SSH_ACCESS_CONFIG ${accessConfig}
          '';
      # The binary is the single source for the ssh drop-in; run the wrapped (config-baked) binary
      # so the emitted ProxyCommand points at itself. (passthru is not part of the derivation hash,
      # so the mutual wrapped<->sshConfig reference is not a cycle.)
      sshConfig = runCommandLocal "kdn-ssh-access-ssh-config" { } ''
        ${wrapped}/bin/kdn-ssh-access emit-ssh-config > "$out"
      '';
    in
    wrapped;

  # The option schema (module.nix), exposed as an embeddable submodule type and a module file.
  passthru.configModule = ./module.nix;
  passthru.configType = lib.types.submodule (import ./module.nix);

  # Validate a module-style config via a small evalModules (types, defaults, edge assertions),
  # then bake it with withConfig. This is the checked entry point.
  passthru.withModule =
    module:
    let
      eval = lib.evalModules {
        modules = [
          ./module.nix
          module
        ];
      };
      cfg = eval.config;
    in
    lib.throwIf (cfg.errors != [ ])
      ("kdn-ssh-access: invalid config:\n  " + lib.concatStringsSep "\n  " cfg.errors)
      (
        finalAttrs.passthru.withConfig {
          inherit (cfg)
            defaults
            identityAgentPatterns
            uplinks
            hosts
            ;
        }
      );

  meta = {
    description = "Topology-aware ssh access dispatcher (host graph: ProxyCommand + ssh wrapper)";
    mainProgram = "kdn-ssh-access";
  };
})
