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
      rev = "306a1b544c544578c0e986a90a16e48f02fd45e6";
      hash = "sha256-R2Zle6uqV/oE3OsA3IIKPGLoEnM/WMwB+eXBD9fU4dw=";
    };
    vendorHash = "sha256-t7g6Tozq/QLq0/5bpXNDCJrOPTjMlvcDUaD6EGqII3Y=";
  };
  all.netclient.nazarewk = {
    inherit version;
    src = fetchFromGitHub {
      owner = "nazarewk";
      repo = "netclient";
      rev = "6aa38082d46ead697135fdc6d1d286a8f5784367";
      hash = "sha256-vNmQPkOOLobZD8fXhcRH9jlGmtIPGZVg1nUpt69I1dM=";
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
