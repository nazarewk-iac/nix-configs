{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.profile.machine.dev;
in {
  options.kdn.profile.machine.dev = {
    enable = lib.mkEnableOption "enable dev machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.desktop.enable = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      jose # JSON Web Token tool, https://github.com/latchset/jose
    ];

    home-manager.users.kdn.kdn.development.cloud.aws.enable = lib.mkDefault true;
    kdn.development.ansible.enable = lib.mkDefault true;
    kdn.development.cloud.azure.enable = lib.mkDefault false;
    kdn.development.cloud.enable = lib.mkDefault true;
    kdn.development.data.enable = lib.mkDefault true;
    kdn.development.db.enable = lib.mkDefault true;
    kdn.development.documents.enable = lib.mkDefault true;
    kdn.development.elixir.enable = lib.mkDefault true;
    kdn.development.golang.enable = lib.mkDefault true;
    kdn.development.java.enable = lib.mkDefault true;
    kdn.development.k8s.enable = lib.mkDefault true;
    kdn.development.llm.online.enable = lib.mkDefault true;
    /*
    TODO: nickel fails to build:
      nickel>   thread 'main' panicked at core/build.rs:44:18:
      nickel>   called `Result::unwrap()` on an `Err` value:
      nickel>   pkg-config exited with status code 1
      nickel>   > PKG_CONFIG_PATH=/nix/store/dfm969c853hhk81bqwm139zl10xmkziy-lix-2.92.0-pre20250118-0795280-dev/lib/pkgconfig:/nix/store/zijk6da9lvwjcgjymgrx4ccxix3jp3zv-boehm-gc-8.2.8-dev/lib/pkgconfig:/nix/store/4nsc733apxj3iqjs7jwq0gwlxgwkdyl6-nlohmann_json-3.11.3/share/pkgconfig:/nix/store/02s02156bw1w1nmlvfwxlr3yw2ihwir1-boost-1.87.0-dev/lib/pkgconfig PKG_CONFIG_ALLOW_SYSTEM_LIBS=1 PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1 pkg-config --libs --cflags nix-store nix-store >= 2.16.0
      nickel>
      nickel>   The system library `nix-store` required by crate `nickel-lang-core` was not found.
      nickel>   The file `nix-store.pc` needs to be installed and the PKG_CONFIG_PATH environment variable must contain its parent directory.
      nickel>   PKG_CONFIG_PATH contains the following:
      nickel>       - /nix/store/dfm969c853hhk81bqwm139zl10xmkziy-lix-2.92.0-pre20250118-0795280-dev/lib/pkgconfig
      nickel>       - /nix/store/zijk6da9lvwjcgjymgrx4ccxix3jp3zv-boehm-gc-8.2.8-dev/lib/pkgconfig
      nickel>       - /nix/store/4nsc733apxj3iqjs7jwq0gwlxgwkdyl6-nlohmann_json-3.11.3/share/pkgconfig
      nickel>       - /nix/store/02s02156bw1w1nmlvfwxlr3yw2ihwir1-boost-1.87.0-dev/lib/pkgconfig
      nickel>
      nickel>   HINT: you may need to install a package such as nix-store, nix-store-dev or nix-store-devel.
      nickel>
      nickel>   note: run with `RUST_BACKTRACE=1` environment variable to display a backtrac
    */
    #kdn.development.nickel.enable = lib.mkDefault true;
    kdn.development.nix.enable = lib.mkDefault true;
    kdn.development.python.enable = lib.mkDefault true;
    kdn.development.rpi.enable = lib.mkDefault true;
    kdn.development.rust.enable = lib.mkDefault true;
    kdn.development.terraform.enable = lib.mkDefault true;
    kdn.development.web.enable = lib.mkDefault true;
    kdn.toolset.ide.enable = lib.mkDefault true;
    kdn.toolset.mikrotik.enable = lib.mkDefault (pkgs.stdenv.hostPlatform.isx86 && config.kdn.desktop.enable);
    services.plantuml-server.enable = lib.mkDefault false; # TODO: fix this?
  };
}
