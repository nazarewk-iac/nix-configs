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
  all.netmaker.nazarewk = {
    inherit version;
    src = fetchFromGitHub {
      owner = "nazarewk";
      repo = "netmaker";
      rev = "630c95c48b43ac8b0cdff1c3de13339c8b322889";
      hash = "sha256-5W9LgzEfGXKz3IBEyMlkorA9TwJ/QKiJSrzkCL/5bXM=";
    };
    vendorHash = "sha256-t7g6Tozq/QLq0/5bpXNDCJrOPTjMlvcDUaD6EGqII3Y=";
  };
  all.netmaker.scripts = {
    inherit version;
    src = fetchFromGitHub {
      owner = "nazarewk";
      repo = "netmaker";
      rev = "630c95c48b43ac8b0cdff1c3de13339c8b322889";
      hash = "sha256-5W9LgzEfGXKz3IBEyMlkorA9TwJ/QKiJSrzkCL/5bXM=";
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
  all.netclient.nazarewk = {
    inherit version;
    src = fetchFromGitHub {
      owner = "nazarewk";
      repo = "netclient";
      rev = "";
      hash = "";
    };
    vendorHash = "";
  };
in
rec {
  inherit version all;
  netmaker = all.netmaker.upstream;
  netmaker-ui = all.netmaker-ui.upstream;
  netclient = all.netclient.upstream;
}
