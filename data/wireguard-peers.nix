{config, ...}: {
  kdn.networking.wireguard.peers = {
    moss = {
      hostnum = 1;
      server = {
        enable = true;
        externalInterface = "ens3";
      };
      cfg = {
        publicKey = "n46g2yMIQ169ZWJk0gpjnhlAlJci6KKv7pxbC6BkqwY=";
        endpoint = "moss.kdn.im:${toString config.kdn.networking.wireguard.port}";
        persistentKeepalive = 25;
        dynamicEndpointRefreshSeconds = 60;
      };
    };
    brys = {
      hostnum = 2;
      cfg = {
        allowedIPs = [
          # "10.0.0.199/32"
        ];
        publicKey = "/lpTqcyUq5Gt9QkMINl+d3yA3i5PzRQM5YJnz/CLpgs=";
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
          # "10.0.0.0/24"
        ];
        publicKey = "+ELclM/EOtnAdfU5qfnoW5jb8UWMvVOP4dJt8ziYRWE=";
      };
    };
    oams = {
      hostnum = 6;
      cfg = {
        publicKey = "sRVjRqcOUYknOBIJXQiA30DYN7zUsWdIvau2xi1uRXw=";
      };
    };
    yelk = {
      hostnum = 6;
      cfg = {
        publicKey = "RTRS8m+gx3g17xWBLXWsxjPsBb+C2aVAk6WI+Hqvil4=";
      };
    };
    etra = {
      hostnum = 7;
      cfg = {
        publicKey = "U3PH63weTZoSDKkQh84QO8g3ruZTKTJdVNpIlrWm6xw=";
      };
    };
  };
}
