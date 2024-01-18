{ lib
, pkgs
, stdenv
, fetchFromGitHub
, fetchpatch
  # build utils
, diffutils
  # implicit dependencies
, coreutils
, dig
, dnsutils
, docker-compose
, gawk
, git
, gnugrep
, jq
, wget
, wireguard-tools
, yq-go
, ...
}:
let
  deps = [
    # implicit dependencies
    coreutils
    dig
    yq-go
    wget
    # see https://github.com/gravitl/netmaker/blob/54a3afc19ac610714d5d4454cd18a06219127b2f/scripts/nm-quick.sh#L383-L422
    git
    wireguard-tools
    dnsutils
    jq
    docker-compose
    gnugrep
    gawk
  ];
in
let
  inputs = import ../inputs.nix { inherit fetchFromGitHub; };
in
stdenv.mkDerivation rec {
  pname = "netmaker-scripts";
  inherit (inputs.all.netmaker.scripts) version src;

  patches = [
    ./remove-compose-links.patch
  ];

  postPatch = ''
    for file in scripts/nm-{quick,upgrade}.sh ; do
      ${gawk}/bin/gawk -i inplace \
        '/\tLATEST=.*/{print;system("cat ${./extra.sh}");next} 1' \
        "$file"
      substituteInPlace "$file" \
        --replace "LATEST=" "LATEST=v${version} # " \
        --replace "BUILD_TYPE='''" "BUILD_TYPE=local" \
        --replace "BUILD_TAG='''" "BUILD_TAG=v${version}" \
        --replace 'BUILD_TAG="$OPTARG"' 'test "$OPTARG" = "$BUILD_TAG" || echo "only $BUILD_TAG is supported!" && exit 1' \
        --subst-var-by "path" "${lib.makeBinPath deps}" \
        --subst-var-by "src" "$out/src/modified"
      echo "###################### $file ######################"
      ${diffutils}/bin/diff "${src}/$file" "$file" || :
    done
  '';

  installPhase = ''
    mkdir -p $out/src/{original,modified}
    cp -a . "$out/src/modified"
    ln -s ${src} "$out/src/original"

    mkdir -p "$out/bin"
    for file in scripts/nm-{quick,upgrade}.sh ; do
      ln -s "../src/modified/$file" "$out/bin/''${file##*/}"
    done
    chmod 555 scripts/nm-{quick,upgrade}.sh
  '';

  passthru.deps = deps;

  meta = with lib;{
    description = "nm-{quick,upgrade}.sh for Netmaker: WireGuard automation from homelab to enterprise";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker/-/releases/v${version}";
    license = licenses.asl20;
    maintainers = with maintainers; [ nazarewk ];
    mainProgram = "nm-quick.sh";
  };
}
