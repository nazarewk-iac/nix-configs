{ config, ... }:
{
  nazarewk.networking.wireguard.peers = {
    wg-0 = {
      hostnum = 1;
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
        publicKey = "FJV0gfKnCpiBEjaLTBp3fHrMSpMUsFSW010KIPedA24=";
      };
    };
    #    nazarewk = {
    #      hostnum = 3;
    #      cfg = {
    #        publicKey = "";
    #      };
    #    };
  };
}
