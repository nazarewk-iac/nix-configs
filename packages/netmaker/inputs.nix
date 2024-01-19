{ fetchFromGitHub, ... }:
let
  version = "0.22.0";
  all.netmaker.upstream = {
    inherit version;
    src = fetchFromGitHub {
      owner = "gravitl";
      repo = "netmaker";
      rev = "v${version}";
      hash = "sha256-uplv/9P7uNYFRLI8LTUXAjKImTtLijsk2gb81vbunXY=";
    };
    vendorHash = "sha256-t7g6Tozq/QLq0/5bpXNDCJrOPTjMlvcDUaD6EGqII3Y=";
  };
  all.netmaker-ui.upstream = {
    inherit version;
    src = fetchFromGitHub {
      owner = "gravitl";
      repo = "netmaker-ui-2";
      rev = "v${version}";
      hash = "sha256-o8uE3kqcIdr0hYJGZQPriOxc52KlxlD9T2UJSkgzCwY=";
    };
    npmDepsHash = "sha256-B7MdaHbwMxZKWc6KARlDqp4tzPVS0O8ChmHfspYR7Co=";
  };
  all.netclient.upstream = {
    inherit version;
    src = fetchFromGitHub {
      owner = "gravitl";
      repo = "netclient";
      rev = "v${version}";
      hash = "sha256-7raWk4Y/ZrSaGKPLrrnD49aDALkZ+Nxycd+px8Eks10=";
    };
    vendorHash = "sha256-lRXZ9iSWQEKWmeQV1ei/G4+HvqhW9U8yUv1Qb/d2jvY=";
  };


  all.netmaker.nazarewk = {
    inherit version;
    src = fetchFromGitHub {
      owner = "nazarewk";
      repo = "netmaker";
      rev = "9ca6b44228847d246dd5617b73f69ec26778f396";
      hash = "sha256-Jy4T7Ncx0i30waP/cy733U1RYWyrNOC1QquQU24jhkY=";
    };
    vendorHash = "sha256-t7g6Tozq/QLq0/5bpXNDCJrOPTjMlvcDUaD6EGqII3Y=";
  };
  all.netclient.nazarewk = {
    inherit version;
    src = fetchFromGitHub {
      owner = "nazarewk";
      repo = "netclient";
      rev = "54cf103a0ee36f725c5b0340ff3953f8340a11d9";
      hash = "sha256-d3b/kQQ/0ZvDhn+SXD88x2e99XQ/Wc5fpYPZ5EzfBzQ=";
    };
    vendorHash = "sha256-lRXZ9iSWQEKWmeQV1ei/G4+HvqhW9U8yUv1Qb/d2jvY=";
  };
in
rec {
  inherit version all;
  netmaker = all.netmaker.nazarewk;
  netmaker-ui = all.netmaker-ui.upstream;
  netclient = all.netclient.nazarewk;
}
