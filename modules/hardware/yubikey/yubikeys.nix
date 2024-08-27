{ lib, config, ... }: {
  kdn.hardware.yubikey.devices.oams = {
    enabled = true;
    serial = "16174038";
    notes = [ "data in KeePass" ];
  };
  /*
    age-plugin-yubikey identies are not sensitive in the meaning
      they cannot be used to decrypt without actual yubikey
        https://github.com/str4d/age-plugin-yubikey/issues/179#issuecomment-2156623271
  */
  #
  # age-plugin-yubikey Slot 1 is PIV Slot 82
  kdn.hardware.yubikey.devices.oams.piv."82" = {
    type = "age-plugin-yubikey";
    age-plugin-yubikey = {
      notes = [ "sops" ];
      name = "age identity 97b9264f";
      pin-policy = "always";
      touch-policy = "cached";
      recipient = "age1yubikey1q05un9a8q2x783srmhv4hm3pjsrxvgrw92q70yyzjmlx3wnd8jwn2x8ghlp";
      identity = "AGE-PLUGIN-YUBIKEY-16M9LVQYZJ7UJVNC8Z7TW7";
    };
  };
  kdn.hardware.yubikey.devices.oams.piv."83" = {
    type = "age-plugin-yubikey";
    age-plugin-yubikey = {
      notes = [ "sops" ];
      name = "age identity 6f7792a6";
      pin-policy = "never";
      touch-policy = "cached";
      recipient = "age1yubikey1qfx38en49qfpyjf5hwn8dch6c0jvvtus29pvwgqlze35rraea00y6dw6rwv";
      identity = "AGE-PLUGIN-YUBIKEY-16M9LVQYRDAME9FSZZVPJA";
    };
  };
  kdn.hardware.yubikey.devices.oams.piv."84" = {
    type = "age-plugin-yubikey";
    age-plugin-yubikey = {
      notes = [ "sops" ];
      name = "age identity aba74437";
      pin-policy = "never";
      touch-policy = "never";
      recipient = "age1yubikey1q25g9xpunct74wnn29dgcgep78q666dkhpfg2flltg92fvyrew02j28464d";
      identity = "AGE-PLUGIN-YUBIKEY-16M9LVQYY4WN5GDCQNHWQ0";
    };
  };
  kdn.hardware.yubikey.devices.brys = {
    enabled = true;
    serial = "16174039";
    notes = [ "data in KeePass" ];
  };
  kdn.hardware.yubikey.devices.brys.piv."82" = {
    type = "age-plugin-yubikey";
    age-plugin-yubikey = {
      notes = [ "sops" ];
      name = "age identity cd6e23c9";
      pin-policy = "always";
      touch-policy = "cached";
      recipient = "age1yubikey1qdppx4kd82ecfxr5lcmgef9w4zxmreyl2q3xv6dsq2jwgv274cm5zmjuy34";
      identity = "AGE-PLUGIN-YUBIKEY-16L9LVQYZE4HZ8JGY5HK5P";
    };
  };
  kdn.hardware.yubikey.devices.brys.piv."83" = {
    type = "age-plugin-yubikey";
    age-plugin-yubikey = {
      notes = [ "sops" ];
      name = "age identity a77792a9";
      pin-policy = "never";
      touch-policy = "cached";
      recipient = "age1yubikey1qf4cjj3ksn60z9hnezkwysvgcll7y3mfxzwzdrzgkfkqe9thmczg6xmmfz9";
      identity = "AGE-PLUGIN-YUBIKEY-16L9LVQYR5AME92GT4N5C3";
    };
  };
  kdn.hardware.yubikey.devices.brys.piv."84" = {
    type = "age-plugin-yubikey";
    age-plugin-yubikey = {
      notes = [ "sops" ];
      name = "age identity 3388da78";
      pin-policy = "never";
      touch-policy = "never";
      recipient = "age1yubikey1q0ke6fjulkqg0x0elweecppfkqqr6cqsr42u8q5k5z6466mu60gjseq6p4t";
      identity = "AGE-PLUGIN-YUBIKEY-16L9LVQYYXWYD57QEX0MMM";
    };
  };
}
