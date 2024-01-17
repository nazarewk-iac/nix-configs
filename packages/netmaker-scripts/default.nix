{ lib
, pkgs
, stdenv
, fetchFromGitHub
, fetchpatch
, dos2unix
, edid-decode
, hexdump
, zsh
}:
let
  deps = with pkgs; [
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
stdenv.mkDerivation rec {
  pname = "netmaker-scripts";
  version = "0.22.0";

  src = pkgs.fetchFromGitHub {
    #owner = "gravitl";
    #repo = "netmaker";
    #rev = "v${version}";
    #hash = "sha256-0KyBRIMXGqg4MdTyN3Kw1rVbZ7ULlfW6M9DSfAUQF8A=";
    owner = "nazarewk";
    repo = "netmaker";
    rev = "630c95c48b43ac8b0cdff1c3de13339c8b322889";
    hash = "sha256-5W9LgzEfGXKz3IBEyMlkorA9TwJ/QKiJSrzkCL/5bXM=";
  };
  patches = [
    ./remove-compose-links.patch
  ];

  postPatch = ''
    for file in scripts/nm-{quick,upgrade}.sh ; do
      ${pkgs.gawk}/bin/gawk -i inplace \
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
      ${pkgs.diffutils}/bin/diff "${src}/$file" "$file" || :
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
    mainProgram = "netmaker";
  };
}
