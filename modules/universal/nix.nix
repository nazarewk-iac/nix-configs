/*
  The value of `kdn.nixConfig`. `./_options.nix` calls this file and passes the module arguments,
  so the settings below read the narrow options an adopter can change.

  This is a plain function, not a module. It declares no option and it emits no config.
*/
{
  config,
  ...
}:
let
  cfg = config.kdn;

  adminUsers = [
    "@wheel" # linux
    "@admin" # macos
  ];
  allowedUsers = [
    "@users" # nixos
    "@staff" # macos
  ];
in
{
  nix.extraOptions = ''
    # run as kdn:
    #   begin; set file nix/nix.sensitive.conf ; pass show "$file" | sudo tee "/etc/$file" >/dev/null && sudo chmod 0640 "/etc/$file" && sudo chown root:wheel "/etc/$file"; end
    !include /etc/nix/nix.sensitive.conf
    !include /etc/nix/nix.access-tokens.auto.conf
  '';

  nix.settings = {
    show-trace = true;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # `kdn.nix.substituters` keeps each URL next to its public key, so the two lists below stay
    # aligned. A substituter with no matching key fails at run time.
    trusted-public-keys = map (entry: entry.publicKey) cfg.nix.substituters;
    substituters = map (entry: entry.url) cfg.nix.substituters;
    allowed-users = adminUsers ++ allowedUsers;
    trusted-users = adminUsers;
    build-dir = "/nix/var/nix/builds";
  };

  nixpkgs.config = {
    allowAliases = true;
    allowUnfree = cfg.nixpkgs.allowUnfree;

    # The list lives in the option default at `./_options.nix`. `types.listOf` concatenates every
    # definition, so a literal here would be a definition an adopter can add to but never remove.
    permittedInsecurePackages = cfg.nixpkgs.permittedInsecurePackages;
  };
}
