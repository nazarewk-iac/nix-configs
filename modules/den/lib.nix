# den as a library — the adopter-facing surface.
#
# It exports two levels:
#
#   1. `imports` — a thin wrapper. It returns a list of plain modules, ready to drop straight into
#      `imports = [ … ];` of a devenv, a nix-darwin or a NixOS module. The caller adopts no den.
#   2. The raw machinery — `nixModule`, `aspectModules`, `eval` and `resolve`. Use it when the thin
#      wrapper is too narrow, for example to declare an aspect of your own.
#
# This uses `den.nixModule`, not `den.flakeModule`. `nixModule` imports four files and exposes
# exactly `{ aspects, lib, policies }`. It has no `den.hosts`, no `den.schema`, no `den.classes` and
# no `den.default`, so none of den's batteries load. `den.flakeModule` imports all of den's
# `modules/` tree, and the batteries live there.
#
# ## The namespace, and the two modules it needs here
#
# Every reusable aspect lives in the `kdn` namespace — see ./namespaces.nix. `nixModule` declares
# neither `den.ful` nor `den.classes`, so a namespace needs two extra modules on this route.
# Measured on 2026-09-10: with both of them, the library route carries a namespace, and den still
# collapses a diamond `includes` to one import.
#
# This route creates the `kdn` namespace **unexported**, and it creates no `personal` namespace at
# all. A consumer's own `modules` may declare aspects in `kdn`; a reference to `personal` fails
# here by design.
#
# Measured on 2026-09-10: for both ported aspects, this route and the `flakeModule` route give one
# identical `drvPath`. See
# ../../docs/tasks/2026-09/generalization/004-den-spike/definition.md.
{
  inputs,
  lib,
}:
let
  # The aspect registry. `flake-module.nix` reads the same attribute set, so the two routes cannot
  # drift apart. One entry per reimplemented slot.
  aspectModules = {
    apps = ./aspects/apps.nix;
    ca = ./aspects/ca.nix;
    desktop-base = ./aspects/desktop-base.nix;
    desktop-kde = ./aspects/desktop-kde.nix;
    desktop-remote-server = ./aspects/desktop-remote-server.nix;
    desktop-sway-kanshi = ./aspects/desktop-sway-kanshi.nix;
    desktop-sway-media-keys = ./aspects/desktop-sway-small.nix;
    desktop-sway-nwg-panel = ./aspects/desktop-sway-nwg.nix;
    desktop-sway-nwg-shell = ./aspects/desktop-sway-nwg.nix;
    desktop-sway-swaylock = ./aspects/desktop-sway-small.nix;
    desktop-sway-swaync = ./aspects/desktop-sway-small.nix;
    desktop-sway-swayr = ./aspects/desktop-sway-small.nix;
    desktop-sway-waybar = ./aspects/desktop-sway-waybar.nix;
    dev-android = ./aspects/dev-android.nix;
    dev-ansible = ./aspects/dev-ansible.nix;
    dev-cloud = ./aspects/dev-cloud.nix;
    dev-cloud-aws = ./aspects/dev-cloud-aws.nix;
    dev-cloud-azure = ./aspects/dev-cloud-azure.nix;
    dev-data = ./aspects/dev-data.nix;
    dev-db = ./aspects/dev-db.nix;
    dev-documents = ./aspects/dev-documents.nix;
    dev-dotnet = ./aspects/dev-dotnet.nix;
    dev-elixir = ./aspects/dev-elixir.nix;
    dev-git = ./aspects/dev-git.nix;
    dev-golang = ./aspects/dev-golang.nix;
    dev-java = ./aspects/dev-java.nix;
    dev-jetbrains = ./aspects/dev-jetbrains.nix;
    dev-k8s = ./aspects/dev-k8s.nix;
    dev-kernel = ./aspects/dev-kernel.nix;
    dev-llm-claude-code = ./aspects/dev-llm-claude-code.nix;
    dev-llm-omp = ./aspects/dev-llm-omp.nix;
    dev-llm-opencode = ./aspects/dev-llm-opencode.nix;
    dev-llm-pi = ./aspects/dev-llm-pi.nix;
    dev-lua = ./aspects/dev-lua.nix;
    dev-nickel = ./aspects/dev-nickel.nix;
    dev-nix = ./aspects/dev-nix.nix;
    dev-nodejs = ./aspects/dev-nodejs.nix;
    dev-python = ./aspects/dev-python.nix;
    dev-rpi = ./aspects/dev-rpi.nix;
    dev-rust = ./aspects/dev-rust.nix;
    dev-shell = ./aspects/dev-shell.nix;
    dev-terraform = ./aspects/dev-terraform.nix;
    dev-web = ./aspects/dev-web.nix;
    devenv-cli = ./aspects/devenv-cli.nix;
    disks = ./aspects/disks.nix;
    disks-persist = ./aspects/disks-persist.nix;
    emulation-wine = ./aspects/emulation.nix;
    fs-luks-zfs = ./aspects/fs.nix;
    fs-watch = ./aspects/fs.nix;
    fs-zfs = ./aspects/fs.nix;
    gh = ./aspects/gh.nix;
    homebrew = ./aspects/homebrew.nix;
    homebrew-nix-managed = ./aspects/homebrew-nix-managed.nix;
    hw-audio = ./aspects/hw-audio.nix;
    hw-basic = ./aspects/hw-basic.nix;
    hw-bluetooth = ./aspects/hw-bluetooth.nix;
    hw-cpu-amd = ./aspects/hw-cpu-amd.nix;
    hw-cpu-intel = ./aspects/hw-cpu-intel.nix;
    hw-edid = ./aspects/hw-edid.nix;
    hw-gpu = ./aspects/hw-gpu.nix;
    hw-gpu-amd = ./aspects/hw-gpu-amd.nix;
    hw-gpu-intel = ./aspects/hw-gpu-intel.nix;
    hw-intel-graphics-fix = ./aspects/hw-intel-graphics-fix.nix;
    hw-modem = ./aspects/hw-modem.nix;
    hw-nanokvm = ./aspects/hw-nanokvm.nix;
    hw-qmk = ./aspects/hw-qmk.nix;
    hw-usbip = ./aspects/hw-usbip.nix;
    hw-yubikey = ./aspects/hw-yubikey.nix;
    jj = ./aspects/jj.nix;
    jj-fork = ./aspects/jj-fork.nix;
    llm = ./aspects/llm.nix;
    llm-client = ./aspects/llm-client.nix;
    llm-proxy = ./aspects/llm-proxy.nix;
    locale = ./aspects/locale.nix;
    managed = ./aspects/managed.nix;
    mcp = ./aspects/mcp.nix;
    mcp-basic-memory = ./aspects/mcp-basic-memory.nix;
    mcp-pretty-print = ./aspects/mcp-pretty-print.nix;
    mcp-snoop = ./aspects/mcp-snoop.nix;
    monitoring-prometheus-stack = ./aspects/monitoring.nix;
    net-dynamic-hosts = ./aspects/net-dynamic-hosts.nix;
    net-interfaces = ./aspects/net-interfaces.nix;
    net-netbird = ./aspects/net-netbird.nix;
    net-openfortivpn = ./aspects/net-openfortivpn.nix;
    net-openvpn = ./aspects/net-openvpn.nix;
    net-resolved = ./aspects/net-resolved.nix;
    net-tailscale = ./aspects/net-tailscale.nix;
    nix = ./aspects/nix.nix;
    nix-config = ./aspects/nix-config.nix;
    nix-remote-builder = ./aspects/nix-remote-builder.nix;
    opencode = ./aspects/opencode.nix;
    outputs-host = ./aspects/outputs.nix;
    packaging-asdf = ./aspects/packaging.nix;
    program-atuin = ./aspects/program-atuin.nix;
    program-beeper = ./aspects/program-beeper.nix;
    program-blender = ./aspects/program-blender.nix;
    program-browsers-launcher = ./aspects/program-browsers-launcher.nix;
    program-chrome = ./aspects/program-chrome.nix;
    program-chromium = ./aspects/program-chromium.nix;
    program-dconf = ./aspects/program-dconf.nix;
    program-direnv = ./aspects/program-direnv.nix;
    program-editors-photo = ./aspects/program-editors-photo.nix;
    program-editors-video = ./aspects/program-editors-video.nix;
    program-ente-photos = ./aspects/program-ente-photos.nix;
    program-firefox = ./aspects/program-firefox.nix;
    program-fish = ./aspects/program-fish.nix;
    program-gnupg = ./aspects/program-gnupg;
    program-handlr = ./aspects/program-handlr.nix;
    program-kdeconnect = ./aspects/program-kdeconnect.nix;
    program-keepass = ./aspects/program-keepass.nix;
    program-keepassxc = ./aspects/program-keepassxc.nix;
    program-logseq = ./aspects/program-logseq.nix;
    program-matrix = ./aspects/program-matrix.nix;
    program-midnight-commander = ./aspects/program-midnight-commander.nix;
    program-nextcloud-client = ./aspects/program-nextcloud-client.nix;
    program-nix-index = ./aspects/program-nix-index.nix;
    program-obs-studio = ./aspects/program-obs-studio.nix;
    program-office = ./aspects/program-office.nix;
    program-orca-slicer = ./aspects/program-orca-slicer.nix;
    program-photoprism = ./aspects/program-photoprism.nix;
    program-rambox = ./aspects/program-rambox.nix;
    program-signal = ./aspects/program-signal.nix;
    program-slack = ./aspects/program-slack.nix;
    program-spotify = ./aspects/program-spotify.nix;
    program-ssh-client = ./aspects/program-ssh-client.nix;
    program-terminal-ide = ./aspects/program-terminal-ide.nix;
    program-thunderbird = ./aspects/program-thunderbird.nix;
    program-tidal = ./aspects/program-tidal.nix;
    program-torrent = ./aspects/program-torrent.nix;
    program-weechat = ./aspects/program-weechat.nix;
    program-wofi = ./aspects/program-wofi.nix;
    program-ydotool = ./aspects/program-ydotool.nix;
    program-zsh = ./aspects/program-zsh;
    rosetta-builder = ./aspects/rosetta-builder.nix;
    secrets = ./aspects/secrets.nix;
    security-disk-encryption = ./aspects/security-disk-encryption.nix;
    security-secrets-age = ./aspects/security-secrets-age.nix;
    security-secrets-sops = ./aspects/security-secrets-sops.nix;
    security-secure-boot = ./aspects/security-secure-boot.nix;
    service-caddy = ./aspects/service-caddy.nix;
    service-coredns = ./aspects/service-coredns.nix;
    service-home-assistant = ./aspects/service-home-assistant.nix;
    service-iperf3 = ./aspects/service-iperf3.nix;
    service-k8s = ./aspects/service-k8s.nix;
    service-k8s-controlplane-lb = ./aspects/service-k8s.nix;
    service-k8s-kubeadm = ./aspects/service-k8s.nix;
    service-k8s-management = ./aspects/service-k8s.nix;
    service-k8s-node = ./aspects/service-k8s.nix;
    service-nextcloud-client = ./aspects/service-nextcloud-client.nix;
    service-postgresql = ./aspects/service-postgresql.nix;
    service-printing = ./aspects/service-printing.nix;
    service-samba = ./aspects/service-samba.nix;
    service-syncthing = ./aspects/service-syncthing.nix;
    service-zammad = ./aspects/service-zammad.nix;
    signing = ./aspects/signing.nix;
    ssh-access = ./aspects/ssh-access.nix;
    ssh-agent = ./aspects/ssh-agent.nix;
    toolset-diagrams = ./aspects/toolset.nix;
    toolset-essentials = ./aspects/toolset.nix;
    toolset-fs = ./aspects/toolset.nix;
    toolset-fs-encryption = ./aspects/toolset.nix;
    toolset-logs-processing = ./aspects/toolset.nix;
    toolset-mikrotik = ./aspects/toolset.nix;
    toolset-network = ./aspects/toolset.nix;
    toolset-network-gui = ./aspects/toolset.nix;
    toolset-nix = ./aspects/toolset.nix;
    toolset-tracing = ./aspects/toolset.nix;
    toolset-unix = ./aspects/toolset.nix;
    user = ./aspects/user.nix;
    virt-containers = ./aspects/virt-containers.nix;
    virt-containers-dagger = ./aspects/virt-containers-dagger.nix;
    virt-containers-distrobox = ./aspects/virt-containers-distrobox.nix;
    virt-containers-docker = ./aspects/virt-containers-docker.nix;
    virt-containers-podman = ./aspects/virt-containers-podman.nix;
    virt-containers-x11docker = ./aspects/virt-containers-x11docker.nix;
    virt-libvirtd = ./aspects/virt-libvirtd.nix;
    virt-microvm-guest = ./aspects/virt-microvm-guest.nix;
    virt-microvm-host = ./aspects/virt-microvm-host.nix;
    virt-vagrant = ./aspects/virt-vagrant.nix;
    zellij = ./aspects/zellij.nix;
  };

  # The namespace name. `namespaces.nix` uses the same one on the `flakeModule` route.
  namespaceName = "kdn";

  # den's namespace machinery is not in `den.nixModule`. Two modules make it reachable:
  #
  #   1. den's own `modules/aspects.nix` declares `den.ful` and `flake.denful`. It needs the `den`
  #      module argument, and `nixModule` supplies that (`_module.args.den = config.den`).
  #   2. `den.classes` needs a declaration, because `namespace.nix` merges each source's classes
  #      into it. Nothing on this route reads the value, so a plain `raw` shim is enough. den's own
  #      declaration lives in `modules/options.nix`, which also declares `den.hosts` and
  #      `den.schema` — importing that file would pull in the entity machinery this route avoids.
  namespaceSupport = [
    (import (inputs.den + "/modules/aspects.nix"))
    {
      options.den.classes = lib.mkOption {
        type = lib.types.lazyAttrsOf lib.types.raw;
        default = { };
        internal = true;
        visible = false;
        description = "A shim for `den.namespace`. See ./lib.nix.";
      };
    }
  ];

  # `nix-effects` is explicit on purpose. den's `nix/lib/fx.nix` otherwise fetches it with
  # `builtins.fetchTarball` at evaluation time, and no consumer lock records that fetch.
  mkInputs =
    extraInputs:
    inputs
    // {
      nix-effects.lib = import inputs.nix-effects { inherit lib; };
    }
    // extraInputs;

  # One den library evaluation. It loads every aspect this repository ships, plus the caller's own
  # den modules.
  eval =
    {
      extraInputs ? { },
      modules ? [ ],
    }:
    let
      denInputs = mkInputs extraInputs;
    in
    (lib.evalModules {
      # `den.nixModule` closes over inputs for den's own use and forwards none. An aspect file that
      # takes `inputs` fails with `attribute 'inputs' missing` without this line.
      specialArgs.inputs = denInputs;
      modules = [
        (inputs.den.nixModule denInputs)
      ]
      ++ namespaceSupport
      ++ [ (inputs.den.namespace namespaceName false) ]
      ++ lib.attrValues aspectModules
      ++ modules;
    }).config.den;

  # Resolve one aspect into a plain module, and assert that it configures something.
  #
  # `den.lib.aspects.resolve` returns `{ imports = [ ]; }` for a whole-aspect function. It gives no
  # warning and no error, so an empty module reaches a caller as a silent no-op. Condition 1 of the
  # 004 spike. Every export goes through this guard.
  resolve =
    den: class: aspect:
    let
      # A whole-aspect function has no `name` attribute, and `or` does not catch the type error
      # that `<function>.name` raises. Test the shape first, so the message below stays reachable.
      name = if lib.isFunction aspect then "<function>" else aspect.name or "<unnamed>";
      module = den.lib.aspects.resolve class aspect;
    in
    if (builtins.length (module.imports or [ ])) > 0 then
      module
    else
      throw ''
        den: the resolved module for aspect `${name}` and class `${class}` has an empty `imports`
        list, so it configures nothing.

        A **whole-aspect** function — `{ host, ... }: { name = …; devenv = …; }` — resolves to an
        empty module across this boundary. den binds an entity argument inside its own evaluation
        only.

        A **per-target** function — `devenv = { host, ... }: …` — resolves to a non-empty module,
        so this guard cannot see it. It then fails inside your own evaluation with `attribute
        'host' missing`. So keep an exported aspect free of entity data, and give it a plain option
        instead. Measured on 2026-09-10.
      '';

  # Every class name that an aspect of this repository emits.
  #
  # This list is a **drift alarm**, not the source of truth. `pairClasses` below reads the class
  # keys off the aspect itself, and it throws when it finds a key this list misses. Measured on
  # 2026-09-11: den declares 14 class names — `nix eval --json '.#den.classes' --apply
  # builtins.attrNames` prints `apps checks darwin devShells devenv hjem homeManager legacyPackages
  # maid nixos os packages user wsl` — and the 21 aspects use these four.
  exportClasses = [
    "nixos"
    "darwin"
    "homeManager"
    "devenv"
  ];

  # The keys den itself puts on a resolved aspect. None of them names a class.
  #
  # Measured on 2026-09-11 with `nix eval --json '.#denful.kdn' --apply 'ns: builtins.mapAttrs
  # (n: v: builtins.attrNames v) ns'`. Both routes give the same 11 keys.
  aspectStructuralKeys = [
    "_"
    "__functor"
    "__providesForwarded"
    "classes"
    "description"
    "excludes"
    "includes"
    "meta"
    "name"
    "policies"
    "provides"
  ];

  # The classes one aspect emits.
  #
  # The **aspect** is the source of truth. den's namespace type is freeform, so it keeps a class
  # key only when the aspect file defines that class. `ca` holds `nixos` alone, and `devenv-cli`
  # holds all four. So an invalid pair gets no key and cannot reach a caller.
  #
  # `aspect.classes` is not the source of truth: it is `[ ]` for every one of the 21 aspects.
  # Measured on 2026-09-11.
  pairClasses =
    den: name:
    let
      classes = lib.subtractLists aspectStructuralKeys (
        builtins.attrNames den.ful.${namespaceName}.${name}
      );
      missed = lib.subtractLists exportClasses classes;
    in
    if missed == [ ] then
      classes
    else
      throw ''
        den: aspect `${name}` emits class ${
          builtins.concatStringsSep ", " (map (c: "`${c}`") missed)
        }, and ./lib.nix does not list it.

        Add the name to `exportClasses` when den gained a class. Add it to `aspectStructuralKeys`
        when den gained a structural key that is not a class. Do not silence this by dropping the
        check: an unlisted class means the pair export omits a real target.
      '';

  # aspect name → the list of classes it emits. This is the list of valid pairs, in one place.
  pairsFor = den: lib.genAttrs (builtins.attrNames aspectModules) (pairClasses den);

  # "<aspect>-<class>" → one already-resolved plain module, one key per valid pair.
  #
  # 30 keys, from 23 aspects. Every value is lazy, and every value goes through the
  # `resolve` guard above, so an empty module cannot reach a caller.
  #
  # Cost, measured on 2026-09-11: the key set alone 1.03 s, one key 0.99 s, all 25 keys of that day 1.02 s.
  # The den evaluation dominates, and `resolve` builds a shallow `{ imports = [ … ]; }`.
  #
  # No two keys can collide. No aspect name ends with `-nixos`, `-darwin`, `-homeManager` or
  # `-devenv`, so the separator is unambiguous. The `throwIf` proves that at evaluation time.
  pairModulesFor =
    den:
    let
      entries = lib.concatMap (
        name:
        map (class: {
          name = "${name}-${class}";
          value = resolve den class den.ful.${namespaceName}.${name};
        }) (pairClasses den name)
      ) (builtins.attrNames aspectModules);
      names = map (entry: entry.name) entries;
    in
    lib.throwIf (builtins.length names != builtins.length (lib.unique names))
      "den: two aspect-class pairs share one export name. See `pairModulesFor` in ./lib.nix."
      (builtins.listToAttrs entries);

  # One den evaluation for the two published attribute sets below. Both stay lazy, so a caller
  # that reads neither pays nothing.
  defaultDen = eval { };
in
{
  inherit
    aspectModules
    eval
    resolve
    namespaceName
    exportClasses
    pairsFor
    pairModulesFor
    ;

  # aspect name → the classes it emits. Read it to list every valid pair with no source read:
  #
  #   nix eval --json '.#denLib.pairs'
  pairs = pairsFor defaultDen;

  # The flat drop-in surface: one key per valid aspect-class pair.
  #
  #   imports = [ inputs.nix-configs.denModules.rosetta-builder-darwin ];
  #
  # `./flake-module.nix` publishes the same shape as `denModules.<aspect>-<class>`, from the flake
  # route's own den handle, so that route pays no second den evaluation. This attribute serves a
  # caller that already holds `denLib` and wants no second entry point.
  #
  # An **invalid** pair is absent, so Nix reports `attribute 'rosetta-builder-nixos' missing`.
  # `pairs` above lists the valid ones.
  pairModules = pairModulesFor defaultDen;

  # den's own library entry point, unwrapped.
  inherit (inputs.den) nixModule;

  # The thin wrapper.
  #
  #   # devenv.nix
  #   { inputs, ... }:
  #   {
  #     imports = inputs.nix-configs.denLib.imports {
  #       class = "devenv";
  #       aspects = [ "gh" ];
  #     };
  #   }
  #
  # `class` names any evaluation domain. den needs no `den.classes` entry for it.
  # `aspects` names entries of `aspectModules` above. Each one resolves through `den.ful.kdn`.
  # `select` takes the den handle and returns a list of aspects, for an aspect of your own. Reach a
  #   namespaced aspect with `d: [ d.ful.kdn.<name> ]`.
  # `modules` adds den modules to the library evaluation, for example a file that declares one.
  # `extraInputs` overrides or adds flake inputs. It defaults to this repository's own inputs, so a
  # caller needs no `nix-rosetta-builder` input of their own.
  imports =
    {
      class,
      aspects ? [ ],
      select ? (_den: [ ]),
      modules ? [ ],
      extraInputs ? { },
    }:
    let
      den = eval { inherit modules extraInputs; };

      # A typo must fail when the caller builds the list, not later when the module system happens
      # to force one element. A `throw` inside `map` stays unevaluated through `builtins.length`,
      # so check every name first and let the `if` carry the throw.
      # The registry is the name list, not `den.ful.kdn`. A namespace attribute set also holds the
      # structural keys `_`, `schema`, `classes` and `stages`, and none of those is an aspect.
      unknown = lib.subtractLists (builtins.attrNames aspectModules) aspects;
      byName =
        if unknown == [ ] then
          map (name: den.ful.${namespaceName}.${name}) aspects
        else
          throw ''
            den: no aspect named ${builtins.concatStringsSep ", " (map (n: "`${n}`") unknown)}.
            Known aspects: ${builtins.concatStringsSep ", " (builtins.attrNames aspectModules)}.
          '';
    in
    map (resolve den class) (byName ++ select den);
}
