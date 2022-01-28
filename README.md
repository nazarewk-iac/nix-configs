# nix-configs
Repository containing my personal Nix (NixOS, Home Manager etc.) configurations

Currently it's just a copy-paste of my learning experience of configuring:
- first-time NixOS
- ZFS
- Sway WM
- ZSH
- Home Manager

I'm planning to slowly migrate to proper structure of the repository moving stuff around.

# Notes

## Interaction between NixOS and Home Manager

- https://jdisaacs.com/blog/nixos-config/

## How to find out what uses the specific store path?

Find immediate parents: `nix-store --query --referrers <paths...>`.

Find the root using paths: `nix-store --query --roots <paths...>`.

Find reverse dependencies: `nix-store --query --referrers <path>` 