{
  pkgs,
  inputs,
  ...
}:
let
  # Render the same fork slot config the check uses, and export its path. A
  # subdir devenv only has its own inputs (nix-configs, nixpkgs), so pass those.
  # inputs.nix-configs is the parent flake: it carries .lib (the extended lib
  # with lib.kdn.mkSlots) and the modules/slots tree.
  jjForkConfigToml = import ./render-fork-config.nix {
    inherit pkgs;
    mkSlots = inputs.nix-configs.lib.kdn.mkSlots;
    slotsPath = inputs.nix-configs + "/modules/slots";
    nixConfigs = inputs.nix-configs;
    extraInputs = inputs;
  };
in
{
  packages = [
    (pkgs.python3.withPackages (ps: [ ps.pytest ]))
    pkgs.jujutsu
    pkgs.git
  ];

  # Export the rendered fork aliases for pytest. Run `pytest -k <case>` in this
  # shell to exercise a single use-case.
  enterShell = ''
    export JJ_FORK_CONFIG_TOML=${jjForkConfigToml}
    echo "jj-experiments: JJ_FORK_CONFIG_TOML=$JJ_FORK_CONFIG_TOML"
  '';
}
