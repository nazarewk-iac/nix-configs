{ lib
, buildNpmPackage
, fetchFromGitHub
, caddy
, nmInputs
, ...
}:
buildNpmPackage rec {
  pname = "netmaker-ui";
  inherit (nmInputs.netmaker-ui) version src npmDepsHash;

  installPhase = ''
    mkdir -p "$out/var" "$out/etc/caddy" "$out/bin"
    mv dist "$out/var/www"
    install -Dm644 ${./Caddyfile} "$out/etc/caddy/Caddyfile"
    install -Dm644 ${./Caddyfile-root} "$out/etc/caddy/Caddyfile-root"
    install -Dm755 ${./netmaker-ui.sh} "$out/bin/netmaker-ui"
    sed -i 's#^caddy#"${lib.getExe caddy}"#g' "$out/bin/netmaker-ui"
  '';

  meta = with lib; {
    description = "WireGuard automation from homelab to enterprise";
    homepage = "https://netmaker.io";
    changelog = "https://github.com/gravitl/netmaker-ui-2/-/releases/v${version}";
    license = licenses.sspl;
    maintainers = with maintainers; [ nazarewk ];
  };
}
