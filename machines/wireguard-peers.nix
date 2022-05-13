{ config, ... }:
{
  nazarewk.networking.wireguard.peers = {
    wg-0 = {
      hostnum = 1;
      server = {
        enable = true;
        externalInterface = "ens3";
      };
      cfg = {
        publicKey = "n46g2yMIQ169ZWJk0gpjnhlAlJci6KKv7pxbC6BkqwY=";
        endpoint = "wg.nazarewk.pw:${toString config.nazarewk.networking.wireguard.port}";
        persistentKeepalive = 25;
        dynamicEndpointRefreshSeconds = 60;
      };
    };
    nazarewk-krul = {
      hostnum = 2;
      cfg = {
        allowedIPs = [
          "10.0.0.199/32"
        ];
        publicKey = "FJV0gfKnCpiBEjaLTBp3fHrMSpMUsFSW010KIPedA24=";
      };
    };
    nazarewk = {
      hostnum = 3;
      cfg = {
        allowedIPs = [
          "10.0.0.210/32"
        ];
        publicKey = "aaMWmmrCQM/wXhV7+i3Igp7D9Rz8jNorEsqt5/zF61s=";
      };
    };
    nazarewk-mi9 = {
      hostnum = 4;
      cfg = {
        publicKey = "K4p1ePw7eWofjAikvsiJPj4Q3QNl6p6lmpRz5BKnvEw=";
      };
    };
    belkin-rt3200-nazarewk = {
      hostnum = 5;
      cfg = {
        allowedIPs = [
          "10.0.0.0/24"
        ];
        publicKey = "xlTLfN0bz8JQ81gMQPxWFVJgCxkeiHKwKxUE15bGVyk=";
      };
    };
  };
}
