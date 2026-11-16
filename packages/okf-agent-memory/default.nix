# `okf-agent-memory`: git-native persistent project memory for AI agents, built on OKF v0.2.
#
# Upstream installs the binary as `okf`. This package renames it to `okf-memory`, because `okf`
# collides with `superops-team/okf` and one of the `okf-mcp` binaries. The tool is pre-1.0, so the
# version is pinned and a bump is a deliberate change.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "okf-agent-memory";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "okf-memory";
    repo = "okf-agent-memory";
    rev = "v${version}";
    hash = "sha256-ireo8tTgc8aC4Hl6MttEKHwEat2oI0vJ91bSbIi+aZ8=";
  };

  # The project declares zero external dependencies, so no vendor hash is needed.
  vendorHash = "sha256-RGNjgNF0u7vhH/49gqbDNGKuGvs2dyFS7u2cjM0VSP0=";

  subPackages = [ "cmd/okf" ];

  postInstall = ''
    mv "$out/bin/okf" "$out/bin/okf-memory"
    install -d "$out/share/okf-agent-memory/skill"
    cp -r .agents/skills/okf-memory/. "$out/share/okf-agent-memory/skill/"
  '';

  meta = {
    description = "Git-native persistent project memory for AI agents on OKF v0.2";
    mainProgram = "okf-memory";
  };
}
