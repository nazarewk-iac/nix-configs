# ClankTalk: a sandboxed, readable scripting runtime for AI agents.
#
# Upstream publishes one npm tarball with no runtime dependencies. The package is therefore an
# unpack-and-wrap build: the tarball already holds `bin/` and `src/js/`, and Node runs the entry
# points directly. Do not use `npx -y` at run time: it resolves a floating version and needs the
# network.
#
# The native harness integrations live inside the same tarball. `passthru.opencodePlugin` is the
# folder an OpenCode V2 plugin loader takes, and `passthru.piExtension` is the file Pi loads with
# `--extension`.
{
  lib,
  stdenv,
  fetchurl,
  makeBinaryWrapper,
  nodejs,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "clank-talk";
  version = "0.1.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/clank-talk/-/clank-talk-${finalAttrs.version}.tgz";
    hash = "sha256-9B0Oqfg5gX9kvSF2gvdWXGfjsXsV6tUPy91SMzDbChM=";
  };

  # NixOS keeps every runtime dependency in /nix/store: a binary's interpreter and shared libraries
  # are in other store paths, not in its own package. The upstream sandbox reads only the program's
  # install folder, so `bwrap` cannot exec a Nix binary (it reports ENOENT for the interpreter).
  # The store is world-readable and immutable, so a read-only bind is safe and makes the sandbox
  # usable on NixOS. The self-test uses the same list, so this also fixes the bwrap probe.
  postPatch = ''
    substituteInPlace src/js/sandbox.js \
      --replace-fail \
        'const SYSTEM_READS = ["/usr", "/bin", "/sbin", "/System", "/Library", "/etc", "/private/etc", "/opt", "/dev", "/lib", "/lib64", "/var/db/timezone", "/private/var/db/timezone"];' \
        'const SYSTEM_READS = ["/usr", "/bin", "/sbin", "/System", "/Library", "/etc", "/private/etc", "/opt", "/dev", "/lib", "/lib64", "/nix/store", "/var/db/timezone", "/private/var/db/timezone"];'

    # A devenv checkout puts Nix store symlinks at the project root (`.mcp.json`, `.claude/settings.json`,
    # `.opencode/plugins/*`). `bwrap` refuses a read-only bind whose destination is a symlink, and the
    # whole sandbox then fails. Skip those symlinks: the root bind already exposes them, and their
    # targets are read-only store paths. `.env` keeps its hide, because a secret must stay hidden.
    node -e '
      const fs = require("fs");
      const path = "src/js/sandbox.js";
      let text = fs.readFileSync(path, "utf8");
      const before = `      } else {\n        args.push("--ro-bind", path, path);\n      }`;
      const after = `      } else if (!(await fs.lstat(path).catch(() => null))?.isSymbolicLink()) {\n        // A Nix store symlink cannot be a bwrap mount destination; its target is read-only.\n        args.push("--ro-bind", path, path);\n      }`;
      if (!text.includes(before)) throw new Error("sandbox.js: hidden-path block not found");
      fs.writeFileSync(path, text.replace(before, after));
    '
  '';

  nativeBuildInputs = [
    makeBinaryWrapper
    nodejs
  ];

  unpackPhase = ''
    runHook preUnpack
    tar xzf "$src" --strip-components=1
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/clank-talk" "$out/bin"
    cp -r . "$out/lib/clank-talk/"

    # The entry points have a `#!/usr/bin/env node` shebang. Wrap the Node binary explicitly, so
    # the package does not depend on the caller's PATH.
    makeBinaryWrapper ${lib.getExe nodejs} "$out/bin/clank-talk" \
      --add-flags "$out/lib/clank-talk/bin/clank-talk.js"
    makeBinaryWrapper ${lib.getExe nodejs} "$out/bin/clank-talk-mcp" \
      --add-flags "$out/lib/clank-talk/bin/clank-talk-mcp.js"

    runHook postInstall
  '';

  passthru = {
    # A folder with no package.json; OpenCode loads its `index` file and the `tui` file beside it.
    opencodePlugin = "${placeholder "out"}/lib/clank-talk/src/js/harnesses/opencode";
    # The Pi extension entry. Pi supplies the optional `typebox` peer from its own runtime.
    piExtension = "${placeholder "out"}/lib/clank-talk/src/js/harnesses/pi.js";
    # The MCP server entry point, for a harness without a native integration.
    mcpServer = "${placeholder "out"}/bin/clank-talk-mcp";
  };

  meta = {
    description = "Sandboxed, readable scripting runtime for AI agents (MCP server, OpenCode plugin, Pi extension)";
    homepage = "https://clank.talk/";
    license = lib.licenses.bsd3;
    mainProgram = "clank-talk";
    platforms = lib.platforms.unix;
  };
})
