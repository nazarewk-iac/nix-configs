{ config, ... }:
{
  kdn.networking.wireguard.peers = {
    moss = {
      hostnum = 1;
      server = {
        enable = true;
        externalInterface = "ens3";
      };
      cfg = {
        publicKey = "n46g2yMIQ169ZWJk0gpjnhlAlJci6KKv7pxbC6BkqwY=";
        endpoint = "wg.nazarewk.pw:${toString config.kdn.networking.wireguard.port}";
        persistentKeepalive = 25;
        dynamicEndpointRefreshSeconds = 60;
      };
    };
    krul = {
      hostnum = 2;
      cfg = {
        allowedIPs = [
          # "10.0.0.199/32"
        ];
        publicKey = "FJV0gfKnCpiBEjaLTBp3fHrMSpMUsFSW010KIPedA24=";
      };
    };
    obler = {
      hostnum = 3;
      cfg = {
        allowedIPs = [
          # "10.0.0.210/32"
        ];
        publicKey = "GYc/ZfHtTbmnWpCD44V37I6PawS9g5WzvnRPXbvwbSs=";
      };
    };
    irp = {
      hostnum = 4;
      cfg = {
        publicKey = "K4p1ePw7eWofjAikvsiJPj4Q3QNl6p6lmpRz5BKnvEw=";
      };
    };
    drek = {
      hostnum = 5;
      cfg = {
        allowedIPs = [
          "10.0.0.0/24"
        ];
        publicKey = "fBy7t2IeoOF+NKuKpPuqp8PtQiMcRldtUnvzzfzarxQ=";
      };
    };
    oams = {
      hostnum = 6;
      cfg = {
        publicKey = "fLuhNEP1GJJgy69FFTmjKbqVJXXT/Q0Pwa58HhPgqg8=";
      };
    };
  };
}
