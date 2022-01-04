{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    ruby_3_0
  ];
}