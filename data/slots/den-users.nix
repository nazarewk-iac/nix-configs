# The owner's three human accounts, as `kdn.users` rows for `modules/den/aspects/user.nix`.
#
# The aspect holds no person's name. This file holds the names and nothing else. An adopter deletes
# it, and the aspect still evaluates with `kdn.users = { }`.
#
# `data/README.md` rule 5 puts the file here: every consumer is a den aspect.
#
# ## No password hash in this file
#
# The old modules inline a hash in a tracked file, and this repository has a public origin. A row
# below sets `hashedPasswordFile` instead, a **runtime** path. nixpkgs types that option
# `nullOr str`, so no evaluation reads the file and no hash reaches the store.
#
# Point each path at your own secret. A sops user writes
# `config.sops.secrets.<name>.path` in the host config, because this file reads no `config`.
#
# ## The payload files
#
# The three key files still live under `modules/universal/profile/user/`. This file points at them
# with a relative path literal, so no key material is duplicated. When that tree goes away, move
# each payload to `data/slots/den-users/<login>/` and add one `.gitignore` negation per file.
#
# ## Nothing imports this file yet
#
# No loader scans `data/`. A host reads the file with a path literal behind
# `builtins.pathExists`. Add that line when a den host takes over the accounts.
{
  # ---------------------------------------------------------------- user 1, the repository owner
  kdn.users.kdn = {
    uid = 31893;
    fullName = "Krzysztof Nazarewski";
    linger = true;
    primary = true;
    nixTrusted = true;
    subordinateIds = "from-uid";
    extraGroups = [
      "adbusers"
      "audio"
      "deluge"
      "dialout"
      "docker"
      "kvm"
      "libvirtd"
      "lp"
      "lpadmin"
      "mlocate"
      "networkmanager"
      "pipewire"
      "plugdev"
      "podman"
      "power"
      "samba"
      "scanner"
      "tty"
      "video"
      "weechat"
      "wheel"
      "wireshark"
      "ydotool"
    ];
    authorizedKeysFile = ../../modules/universal/profile/user/kdn/.ssh/authorized_keys;
    gpgPublicKeysFile = ../../modules/universal/profile/user/kdn/gpg-pubkeys.txt;
    u2fKeysFile = ../../modules/universal/profile/user/kdn/yubico/u2f_keys.parts;
    # hashedPasswordFile = "/run/secrets/users/kdn/hashed-password";
  };

  # ---------------------------------------------------------------- user 2
  kdn.users.bn = {
    uid = 27748;
    fullName = "Beata";
    extraGroups = [
      "audio"
      "dialout"
      "lp"
      "lpadmin"
      "mlocate"
      "networkmanager"
      "pipewire"
      "plugdev"
      "power"
      "scanner"
      "tty"
      "video"
    ];
    u2fKeysFile = ../../modules/universal/profile/user/bn/yubico/u2f_keys.parts;
    # hashedPasswordFile = "/run/secrets/users/bn/hashed-password";
  };

  # ---------------------------------------------------------------- user 3
  kdn.users.sn = {
    uid = 48378;
    fullName = "Staś";
    extraGroups = [
      "audio"
      "dialout"
      "lp"
      "lpadmin"
      "mlocate"
      "networkmanager"
      "pipewire"
      "plugdev"
      "power"
      "scanner"
      "tty"
      "video"
    ];
    u2fKeysFile = ../../modules/universal/profile/user/sn/yubico/u2f_keys.parts;
    # hashedPasswordFile = "/run/secrets/users/sn/hashed-password";
  };
}
