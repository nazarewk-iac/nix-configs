{
  pkgs,
  lib,
}: {
  src, # ./.
  name, # some-thing
  python, # pkgs.python313
  # defaults
  imageName ? name,
  scriptFile ? (src + /${name}.py),
  requirementsFile ? (src + /requirements.txt),
  devRequirementsFile ? (src + /requirements.dev.txt),
  containerTag ? "latest",
  devPackages ? (pp: with pp; [pip-chill]),
  packageOverrides ? (final: prev: {
    #  htpy = lib.customisation.callPackageWith (pkgs // prev) ./htpy {};
  }),
  runtimeDeps ? [],
  makeWrapperArgs ? [],
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
      (builtins.map (builtins.match "^([[:alnum:]_-]+).*$"))
      lib.lists.flatten
      (builtins.filter (line: line != "" && line != null))
    ];

  mkPythonDeps = path: pp: builtins.map (pkgName: pp."${pkgName}") (readRequirementNames path);

  pythonInstance = python.override {inherit packageOverrides;};

  mkEnv = depsFn:
    lib.pipe pythonInstance [
      (p:
        p.buildEnv.override {
          extraLibs = depsFn p.pkgs;
        })
      (env:
        if runtimeDeps == []
        then env
        else
          pkgs.runCommand "${env.name}-with-runtime-deps" {
            meta.mainProgram = env.executable;
            unwrapped = env;
            nativeBuildInputs = with pkgs; [
              makeBinaryWrapper
            ];
          } ''
            mkdir -p "$out/bin"
            for binary in "$unwrapped"/bin/* ; do
              if test -d "$binary" || ! test -x "$binary" ; then
                continue
              fi
              binName="''${binary##*/}"
              makeBinaryWrapper "$binary" "$out/bin/$binName" \
                 --inherit-argv0 \
                 ${lib.strings.escapeShellArgs makeWrapperArgs} \
                 --prefix PATH : '${lib.makeBinPath runtimeDeps}'
            done
          '')
    ];

  releaseEnv = mkEnv (mkPythonDeps requirementsFile);
  devEnv = mkEnv (pp:
    (mkPythonDeps requirementsFile pp)
    ++ (mkPythonDeps devRequirementsFile pp)
    ++ (devPackages pp));

  extraOutputs = {
    python = pythonInstance;
    inherit
      devRequirementsFile
      mkPythonDeps
      requirementsFile
      ;
    releaseEnv = releaseEnv;
    devEnv = devEnv;

    container = pkgs.dockerTools.buildImage (imageOverlay {
      name = imageName;
      tag = "latest";
      copyToRoot = pkgs.buildEnv (imageBuildEnvOverlay {
        name = "image-root";
        paths = [script releaseEnv] ++ runtimeDeps;
        pathsToLink = ["/bin"];
      });
      config.Entrypoint = imageEntrypoint;
      config.Env = lib.attrsets.mapAttrsToList (name: value: "${name}=${value}") imageEnv;
    });
  };
  pythonWriter = pkgs.writers.makeScriptWriter {
    interpreter = lib.getExe releaseEnv;
  };
  script = lib.trivial.pipe scriptFile [
    (pythonWriter "/bin/${name}")
    (pkg: pkg // extraOutputs)
  ];
in
  script
