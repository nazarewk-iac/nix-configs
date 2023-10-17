{ pkgs, lib, ... }:
let
  pyproject = builtins.fromTOML (builtins.readFile attrs.common.pyproject);
  poetryName = pyproject.tool.poetry.name;

  attrs.common = {
    python = pkgs."python311";
    projectDir = ./.;
    pyproject = ./pyproject.toml;
    poetrylock = ./poetry.lock;
    overrides = pkgs.poetry2nix.defaultPoetryOverrides.extend (final: prev: {
      # shshsh = prev.shshsh.overridePythonAttrs (old: { buildInputs = (old.buildInputs or [ ]) ++ [ final.poetry ]; });
      # yubikey-manager = prev.yubikey-manager.overridePythonAttrs (old: { buildInputs = (old.buildInputs or [ ]) ++ [ final.poetry ]; });
    });
  };

  attrs.app = attrs.common // {
    buildInputs = with pkgs; [
      # additional non-python dependencies
      #jq
      #difftastic
    ];
  };
  attrs.env = attrs.common // {
    # groups = [ "dev" "test" ];
    editablePackageSources = { "${poetryName}" = attrs.common.projectDir; };
  };

  envvars = {
    # additional environment variables to set for the tools
  };

  poetryApp = pkgs.poetry2nix.mkPoetryApplication attrs.app;
  poetryEnv = pkgs.poetry2nix.mkPoetryEnv attrs.env;

  app = wrap {
    name = poetryName;
    paths = [ poetryApp ];
  };
  dev = wrap {
    name = "dev-${poetryName}";
    paths = [ poetryEnv ] ++ attrs.app.buildInputs;
  };

  wrap = { name, paths, env ? envvars, initScript ? "" }:
    let
      wrapper =
        let
          drv = pkgs.writeShellApplication {
            name = "${name}-wrapper";
            text =
              let
                bashEnv =
                  let
                    envToBash = name: value: "export ${name}=${lib.escapeShellArg (toString value)}";
                  in
                  lib.pipe env [
                    (lib.mapAttrsToList envToBash)
                    (lib.concatStringsSep "\n")
                  ];
              in
              ''
                src="''${BASH_SOURCE[0]}"
                dir="''${BASH_SOURCE[0]%/*}"

                var="${placeholder "out"}"
                # strip /nix/store/
                var="''${var#/nix/store/}"
                # uppercase
                var="''${var^^}"
                # dash to underscore
                var="''${var//"-"/"_"}"
                # prefix
                var="_WRAPPER_ACTIVATED_$var"

                if [ "''${!var:-"no"}" != "yes" ] ; then
                  export "$var"="yes"
                  export PATH="$dir/.wrapped:$PATH"
                  ${bashEnv}
                  ${initScript}
                fi
                exec "$dir/.wrapped/''${src##*/}" "$@"
              '';
          };
        in
        "${drv}/bin/${name}-wrapper";
    in
    pkgs.symlinkJoin {
      name = "${name}-newsymlinks";
      paths = paths;
      postBuild = ''
        mv "$out/bin" "$out/.wrapped"
        mkdir -p "$out/bin"
        mv "$out/.wrapped" "$out/bin/.wrapped"
        for file in "$out/bin/.wrapped"/* ; do
          ln -s "${wrapper}" "$out/bin/''${file##*/}"
        done
      '';
    };
  container = pkgs.nix2container.buildImage {
    name = "localhost/eid";
    tag = "latest";
    config.entrypoint = [ "${app}/bin/eid" ];
    copyToRoot = pkgs.buildEnv {
      name = "${poetryName}-container-root";
      paths = [ app ];
      pathsToLink = [ "/bin" ];
    };
    layers = builtins.map
      (deps: pkgs.nix2container.buildLayer { deps = lib.lists.flatten deps; })
      [
        [
          attrs.app.python
          attrs.app.buildInputs
        ]
      ];
  };
in
{
  inherit attrs pyproject;
  inherit poetryApp poetryEnv;
  inherit app dev container;
  inherit (attrs.common) python;
}
