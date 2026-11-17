# The brys accounts for the den implementation. DEN-ONLY, TEST-ONLY passwords.
#
# Passwords live in `pass` under `hosts/brys/users/<name>/password`, so a human can log in over the
# KVM or SSH and recover a failed boot. The rows below carry the yescrypt **hash** of those
# passwords: a hash is not a secret, and a build-time hash keeps the host free of any boot-time
# secret dependency, which is the property this port must preserve.
#
# `root` feeds `kdn.profile-baseline.rootHashedPasswordFile` through the `user-profiles` aspect; the
# row never becomes a normal account.
{
  kdn.userProfileData = {
    kdn = {
      uid = 31893;
      fullName = "Krzysztof Nazarewski";
      email = "gpg@kdn.im";
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
      linger = true;
      primary = true;
      nixTrusted = true;
      subordinateIds = "from-uid";
      passwordHash = "$y$j9T$7PSnpVJejBXUIq5DDe9Ok/$63Pd2HBPZAZVURD2lpob4duqu6UmHT7.NCSJKjgpb8C";
      authorizedKeys = [
        "ssh-rsa ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAYEAvM4y0G5vZ2OYlSeGn2w7y/s+VZMzhGGb9rlUkDtWtwvsE2TWlApFyHggn6qObmQ5DUOu0Mhy6l/ojylyp2Q/C7FMoQWkeBorLKvxf8KFE1lJktCXCxJyptDn8kkNi6Fxszig/flrp5lSWWjDCafyVeyFhvMo22fblzjPOG//wu0+RnOLn9eiWC2CUvJjG11AH+AxWI4UMXY93gq5K1YVLd3EmhI/L1ITAoY3cXoheP0TW9epqe0Zq6lGO+gLiYeWgZJiolSqcHCkTzopbkIZ2cP+yEdeJrYp8ibdO7H0oyXOy48yPElkEobcISzQmTayXQfXyr9YzFPGdM0ZxxKPfpmMox2DTL+mpo1etLOf7ihJNBoR6aAcAWeYLdfqmIlWnVVySW1RPcq31tR4uCP6jpDsbEArXP7lttkWzb0EuBRKN94OVsl7gHuqSSdnrWJwU6jn8EAi9krRQtOKUrz62nOmAkWIe/4fM/3CVjuOgTSUkmuu15SgrbN9aLYp0ct/ nazarewk.id_rsa"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFngB2F2qfcXVbXkssSWozufmyc0n6akKYA8zgjNFdZ"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIMd210LnL8ntJhjzlOC7jreDmiyEuW5HiQPUchGJ/YlhAAAABHNzaDo="
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIHrC85HuMRil8BY8PiGpmpMQDe2NX1vD6lqR+zjkpM7XAAAABHNzaDo="
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAILxMb1sJj1iWynnKF8koeRDWUNVlEjdqMXt1Y1WL9JzTAAAABHNzaDo="
      ];
    };

    # The local super-user. `pass show hosts/brys/users/root/password`.
    root = {
      passwordHash = "$y$j9T$EP8SIEFHbVCyF417vEdma/$HH.Uz0SLylCfqLYqsQORncagmUNBUsnp3KflVv2Bqq5";
    };
  };
}
