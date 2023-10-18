{ lib
, buildGoModule
, fetchFromGitHub
, ...
}:
let
  #commit = "b0b6aaadcb15dd5a35f3677db6bd8529037a568f";
  #sha256 = "sha256-k0cIF8GWVmsX0C/DzCoVpKz5s2jJsnnsK6lJfv8J1UM=";
  #vendorSha256 = "sha256-CWoyeom5kmMf5PceXUkay/NTNj286wYrkG23rsmREpc=";
  commit = "6539e2343c1601e0a3de318c784d77b2d8fb9a3d";
  sha256 = "sha256-SyDb14lehaTQ+/yWpFb+93Yy/AaNtN5pEqzzH+vtpmA=";
  vendorSha256 = "sha256-j5/08CEPBdFcJg/2weBpV4gG2STH6ZNJ3odaFa4r5NQ=";
in
buildGoModule {
  pname = "tc-redirect-tap";

  version = "2023-09-07-${commit}";
  inherit vendorSha256;

  src = fetchFromGitHub {
    #owner = "awslabs";
    owner = "nazarewk";
    repo = "tc-redirect-tap";
    rev = commit;
    inherit sha256;
  };
  postPatch = ''
    cat go.mod
    #substituteInPlace go.mod --replace "go 1.11" "go 1.17"
    #go mod tidy
  '';

  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "tc-redirect-tap is a CNI plugin. This plugin allows you to adapt pre-existing CNI plugins/configuration to a tap device.";
    homepage = "https://github.com/awslabs/tc-redirect-tap/";
    license = licenses.asl20;
    maintainers = with maintainers; [ nazarewk ];
  };
}
