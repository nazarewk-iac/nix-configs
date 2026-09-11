# The seed file of ./default.nix's directory scan, and the template a later batch copies.
#
# It proves two things at once: the scan really finds a file and turns it into a check, and every
# name `../harness.nix` exports arrives here. A missing export throws at evaluation, so this set is
# the tripwire for a rename.
#
# It reads an option value only. It forces no `drvPath`, because `den-eval-instantiate` already
# forces all 26 (aspect, class) pairs and that check costs 58 s.
#
# This file ports no aspect, so `instantiatedBy` stays empty. A row must name a registry aspect;
# `den-eval-coverage` compares the merged table with the registry, key for key.
{
  pkgs,
  lib,
  inputs,
  denLib,
  harness,
  ...
}:
let
  inherit (harness)
    bareNixos
    bareDarwinSystem
    bareDarwin
    bareShell
    bareHome
    bareHomeConfiguration
    forceOf
    mkEvalCheck
    ;

  sorted = builtins.sort (a: b: a < b);
in
{
  instantiatedBy = { };

  assertions = [
    {
      name = "forceOf holds one bare harness per den class";
      expected = [
        "darwin"
        "devenv"
        "homeManager"
        "nixos"
      ];
      actual = sorted (builtins.attrNames forceOf);
    }
    {
      name = "the three function-only exports arrive";
      expected = {
        bareDarwin = true;
        bareHome = true;
        mkEvalCheck = true;
      };
      actual = {
        bareDarwin = lib.isFunction bareDarwin;
        bareHome = lib.isFunction bareHome;
        mkEvalCheck = lib.isFunction mkEvalCheck;
      };
    }
    {
      name = "each whole-evaluation harness reads back its own bare consumer data";
      expected = {
        darwinSystem = "den";
        homeConfiguration = "dev";
        nixos = "x86_64-linux";
        shell = "den-mvp-bare";
      };
      actual = {
        darwinSystem = (bareDarwinSystem [ ]).config.system.primaryUser;
        homeConfiguration = (bareHomeConfiguration [ ]).config.home.username;
        nixos = (bareNixos [ ]).config.nixpkgs.hostPlatform.system;
        shell = (bareShell { }).config.name;
      };
    }
    {
      name = "the scan passes pkgs, lib, inputs and denLib to an area file";
      expected = {
        denLib = true;
        inputs = true;
        lib = true;
        pkgs = true;
      };
      actual = {
        denLib = denLib ? imports;
        inputs = inputs ? self;
        lib = lib ? mkIf;
        pkgs = pkgs ? runCommand;
      };
    }
  ];
}
