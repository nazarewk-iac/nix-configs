{ fetchFromGitHub, ... }: rec {
  /*
    see for dependencies:
    - https://hub.docker.com/u/gravitl
  */
  version = "0.22.0";
  netmaker = {
    src = fetchFromGitHub {
      #owner = "gravitl";
      #repo = "netmaker";
      #rev = "v${version}";
      #hash = "sha256-0KyBRIMXGqg4MdTyN3Kw1rVbZ7ULlfW6M9DSfAUQF8A=";
      owner = "nazarewk";
      repo = "netmaker";
      rev = "630c95c48b43ac8b0cdff1c3de13339c8b322889";
      hash = "sha256-5W9LgzEfGXKz3IBEyMlkorA9TwJ/QKiJSrzkCL/5bXM=";
    };
    vendorHash = "sha256-t7g6Tozq/QLq0/5bpXNDCJrOPTjMlvcDUaD6EGqII3Y=";
  };
  netclient = {
    src = fetchFromGitHub {
      owner = "gravitl";
      repo = "netclient";
      rev = "v${version}";
      hash = "sha256-7raWk4Y/ZrSaGKPLrrnD49aDALkZ+Nxycd+px8Eks10=";
      #      owner = "nazarewk";
      #      repo = "netclient";
      #      rev = "630c95c48b43ac8b0cdff1c3de13339c8b322889";
      #      hash = "sha256-5W9LgzEfGXKz3IBEyMlkorA9TwJ/QKiJSrzkCL/5bXM=";
    };
    vendorHash = "sha256-lRXZ9iSWQEKWmeQV1ei/G4+HvqhW9U8yUv1Qb/d2jvY=";
  };
}
