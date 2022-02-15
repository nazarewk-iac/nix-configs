# nix-configs
Repository containing my personal Nix (NixOS, Home Manager etc.) configurations.

Basic structure:
- `configurations/` - large NixOS configuration bundles
- `machines/` - configurations of specific (physical) machines
- `users/` - user specific profiles
- `modules/` - all modules live here, they MUST be turned off by default (side-effect free imports),
  - `modules/default.nix` - holds imports to all the modules and basic Nix package manager configuration,

Generally I aim to hide everything behind Options, but bulk of configuration still lives in `configurations/desktop`. 


## Overview

This is incomplete list of incorporated software/systems worth noting:
- ZFS
- Sway WM
- ZSH
- Home Manager

# Notes

## Interaction between NixOS and Home Manager

- https://jdisaacs.com/blog/nixos-config/

## How to find out what uses the specific store path?

Find immediate parents: `nix-store --query --referrers <paths...>`.

Find the root using paths: `nix-store --query --roots <paths...>`.

Find reverse dependencies: `nix-store --query --referrers <path>` 