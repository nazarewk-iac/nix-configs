{
  lib,
  config,
  ...
}: let
  cfg = config.k8s.clusters.pic;
in {
  config.k8s.clusters.pic = {
    enable = lib.mkDefault true;
    allowedVersions = ["1.35"];
    domain = "pic.int.kdn.im";

    apiserver.vrrp.masterNode = "pwet";
    apiserver.vrrp.id = 90;
    apiserver.vrrp.ipv4 = "10.92.0.7/24";
    apiserver.vrrp.ipv6 = "fd12:ed4e:366d:eb17:a70f:ea4e:f6f1:f6bf/64";
    apiserver.port.internal = 28635;
    apiserver.port.shared = 29037;
    apiserver.interface = "pic";
    apiserver.domain = "k8s.pic.etra.net.int.kdn.im";
    controlplane.nodes = ["pwet" "turo" "yost"];
    worker.nodes = ["pwet" "turo" "yost"];
    subnet.pod = [
      "fd12:ed4e:366d:5224::/64"
      "10.209.0.0/16"
    ];
    subnet.service = [
      "fd31:e17c:f07f:2dc0:4e2b:2ebc:cbc0:0/108"
      "10.213.0.0/16"
    ];
  };
}
