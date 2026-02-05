{
  pkgs,
  lib,
}: {
  src, # ./.
  name, # some-thing
  python, # pkgs.python313
  # defaults
  imageName ? name,
  pythonModule ? "",
  scriptFile ? (
    # TODO: switch this to running python module directly instead?
    if builtins.pathExists (src + /${name}.py)
    then (src + /${name}.py)
    else pkgs.writeText "${name}-script.py" scriptFileText
  ),
  scriptFileText ? "",
  pyproject ? (
    if builtins.pathExists (src + /pyproject.toml)
    then src + /pyproject.toml
    else
      pkgs.writers.writeTOML "${name}-pyproject.toml" (
        pyprojectData
        // {
          build-system =
            {
              requires = ["hatchling >= 1.26"];
              build-backend = "hatchling.build";
            }
            // (pyprojectData.build-system or {});
          project =
            {
              name = name;
              version = "0.0.1";
            }
            // (pyprojectData.build-system or {});
        }
      )
  ),
  pyprojectData ? {},
  requirementsFile ? (
    if builtins.pathExists (src + /requirements.txt)
    then src + /requirements.txt
    else pkgs.writeText "${name}-requirements.txt" requirementsFileText
  ),
  requirementsFileText ? "",
  devRequirementsFile ? (src + /requirements.dev.txt),
  containerTag ? "latest",
  devPackages ? (pp: with pp; [pip-chill]),
  packageOverrides ? (
    final: prev: {
      #  htpy = lib.customisation.callPackageWith (pkgs // prev) ./htpy {};
    }
  ),
  runtimeDeps ? [],
  makeWrapperArgs ? [],
  buildEnvOverride ? old: old,
  imageEntrypoint ? ["/bin/${name}"],
  imageEnv ? {},
  imageOverlay ? old: old,
  imageBuildEnvOverlay ? old: old,
  ...
}: let
  readRequirementNames = path:
    lib.trivial.pipe path [
      (p:
        if builtins.pathExists p
        then builtins.readFile p
        else "")
      (lib.strings.splitString "\n")
      (map (builtins.match "^([[:alnum:]_-]+).*$"))
      lib.lists.flatten
      (builtins.filter (line: line != "" && line != null))
    ];

  mkPythonDeps = path: pp: map (pkgName: pp."${pkgName}") (readRequirementNames path);

  pythonInstance = python.override {inherit packageOverrides;};

  generatedSrc = pkgs.symlinkJoin {
    name = "${name}-src";
    paths = [
      src
      (pkgs.runCommand "${name}-src-generated" {} ''
        mkdir -p "$out"
        cd "$out"
        ln -s ${pyproject} pyproject.toml
        ln -s ${requirementsFile} requirements.txt
      '')
    ];
  };

  mkPackageFor = depsFn: python: (python.pkgs.buildPythonPackage {
    pname = name;
    version = "0.0.1";
    pyproject = true;
    src = generatedSrc;
    buildInputs = with python.pkgs; [
      hatchling
    ];

    dependencies = depsFn python.pkgs;
  });

  mkEnv = depsFn:
    lib.pipe pythonInstance [
      (
        p:
          p.buildEnv.override (
            old:
              buildEnvOverride (
                old
                // {
                  extraLibs =
                    (old.extraLibs or [])
                    ++ [(mkPackageFor depsFn p)];
                }
              )
          )
      )
      (
        env: let
          wrapperArgs = lib.lists.flatten [
            # ["--inherit-argv0" ] # TODO: re-enable after fix https://github.com/NixOS/nixpkgs/issues/461884
            makeWrapperArgs
            ["--prefix" "PATH" ":" (lib.makeBinPath runtimeDeps)]
          ];
        in
          if runtimeDeps == []
          then env
          else
            pkgs.runCommand "${env.name}-with-runtime-deps"
            {
              meta.mainProgram = env.executable;
              unwrapped = env;
              nativeBuildInputs = with pkgs; [
                makeBinaryWrapper
              ];
            }
            ''
              mkdir -p "$out/bin"
              for binary in "$unwrapped"/bin/* ; do
                if test -d "$binary" || ! test -x "$binary" ; then
                  continue
                fi
                binName="''${binary##*/}"
                makeBinaryWrapper "$binary" "$out/bin/$binName" ${lib.strings.escapeShellArgs wrapperArgs}
              done
            ''
      )
    ];

  releaseRequirementsFn = mkPythonDeps requirementsFile;
  devRequirementsFn = mkPythonDeps devRequirementsFile;
  releaseEnv = mkEnv releaseRequirementsFn;
  devEnv = mkEnv (
    pp: (releaseRequirementsFn pp) ++ (devRequirementsFn pp) ++ (devPackages pp)
  );

  extraOutputs = {
    python = pythonInstance;
    inherit
      devRequirementsFile
      mkPythonDeps
      requirementsFile
      ;
    inherit
      releaseRequirementsFn
      devRequirementsFn
      ;
    mkPackageForPythonPackages = mkPackageFor releaseRequirementsFn;

    inherit
      generatedSrc
      releaseEnv
      devEnv
      ;

    releaseEnvUnwrapped = releaseEnv.unwrapped;

    container = pkgs.dockerTools.buildImage (imageOverlay {
      name = imageName;
      tag = "latest";
      copyToRoot = pkgs.buildEnv (imageBuildEnvOverlay {
        name = "image-root";
        paths =
          [
            script
            releaseEnv
          ]
          ++ runtimeDeps;
        pathsToLink = ["/bin"];
      });
      config.Entrypoint = imageEntrypoint;
      config.Env = lib.attrsets.mapAttrsToList (name: value: "${name}=${value}") imageEnv;
    });
  };
  script =
    (
      if pythonModule != ""
      then
        (pkgs.writeShellApplication {
          name = name;
          text = '''${lib.getExe releaseEnv}' -m '${pythonModule}' "$@"'';
        })
      else
        (pkgs.writers.makeScriptWriter {interpreter = lib.getExe releaseEnv;} "/bin/${name}" (
          builtins.readFile scriptFile
        ))
    )
    // extraOutputs;
in
  script
