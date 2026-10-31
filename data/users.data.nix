# The owner's human accounts, as one structured data file.
#
# This is a **pure data value**, not a module: it declares no option and imports nothing. A host
# imports it into an option and selects the profiles it wants. The shape is one attribute per
# login name; each attribute is a row that feeds a `kdn.users.<name>` entry.
#
# `data/README.md` rule 3 puts it under the top level because a consumer is a den aspect (rule 5
# also matches once a `user-profiles` aspect reads it). It holds the owner's personal values, so an
# adopter replaces or deletes it.
#
# ## Fields
#
# | Field | Meaning |
# |---|---|
# | `uid` | numeric id |
# | `fullName` | display name and GECOS |
# | `email` | commit identity; read by `dev-git`/`signing`, not by the account |
# | `extraGroups` | supplementary groups, filtered to groups the host declares |
# | `linger` / `primary` / `nixTrusted` / `subordinateIds` | the `kdn.users` row switches |
# | `passwordHash` | the yescrypt/crypt hash, written to a file by the aspect |
# | `passwordHashFile` | optional path override (a sops secret); wins over `passwordHash` |
# | `authorizedKeysFile` | SSH keys payload |
# | `u2fKeysFile` / `gpgPublicKeysFile` | YubiKey and GPG payloads |
#
# The hashes are the same values the old universal tree ships in its module files. Keeping them
# here is the whole point of this file: the old tree repeats them, and a den host should not.
{
  kdn.userProfileData = {
    kdn = {
      uid = 31893;
      fullName = "Krzysztof Nazarewski";
      email = "gpg@kdn.im";
      extraGroups = [
        "adbusers" "audio" "deluge" "dialout" "docker" "kvm" "libvirtd" "lp" "lpadmin"
        "mlocate" "networkmanager" "pipewire" "plugdev" "podman" "power" "samba"
        "scanner" "tty" "video" "weechat" "wheel" "wireshark" "ydotool"
      ];
      linger = true;
      primary = true;
      nixTrusted = true;
      subordinateIds = "from-uid";
      passwordHash = "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
      authorizedKeysFile = ../modules/universal/profile/user/kdn/.ssh/authorized_keys;
      gpgPublicKeysFile = ../modules/universal/profile/user/kdn/gpg-pubkeys.txt;
      u2fKeysFile = ../modules/universal/profile/user/kdn/yubico/u2f_keys.parts;
    };

    bn = {
      uid = 27748;
      fullName = "Beata";
      extraGroups = [
        "audio" "dialout" "lp" "lpadmin" "mlocate" "networkmanager"
        "pipewire" "plugdev" "power" "scanner" "tty" "video"
      ];
      passwordHash = "$6$rounds=4096$KyC.856JV99or3zx$X2wYf1M6rO3xqDkOlMwFaAJvgiIUewc/LtWEPNCgZUBQceFlNsgEw1IgZmjduFE41IFdJWKqKuroUAznvE0Sx0";
      u2fKeysFile = ../modules/universal/profile/user/bn/yubico/u2f_keys.parts;
    };

    sn = {
      uid = 48378;
      fullName = "Staś";
      extraGroups = [
        "audio" "dialout" "lp" "lpadmin" "mlocate" "networkmanager"
        "pipewire" "plugdev" "power" "scanner" "tty" "video"
      ];
      passwordHash = "$y$j9T$WGU0Qrlm0.jq7Y4QfyVYC0$HiYyLZMDX8M/A7WNshB5PjtZEGufQ.Qa93FY4WIlcw8";
      u2fKeysFile = ../modules/universal/profile/user/sn/yubico/u2f_keys.parts;
    };

    # The local super-user. Its hash is the same one the old baseline ships.
    root = {
      passwordHash = "$y$j9T$AhbnpYZawNWNGfuq1h9/p0$jmitwtZwTr72nBgvg2TEmrGmhRR30sQ.hQ7NZk1NqJD";
    };
  };
}
