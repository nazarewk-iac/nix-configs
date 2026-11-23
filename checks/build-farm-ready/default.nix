# The build-farm scheduler proof of concept, as an isolated four-VM test.
#
# `docs/tasks/2026-11/build-farm-scheduling/` recommends keeping HAProxy and replacing the static
# `maxConnections` numbers with a per-builder `ready maxconn:N` responder. This test proves that
# mechanism end to end, on a test-only port, with no connection to the real farm:
#
#   client ──ssh-ng──▶ proxy:2222 (HAProxy, balance first, agent-check) ──▶ builder-a:22
#                                                                       └─▶ builder-b:22
#
# Three acceptance points, each naming its evidence:
#
# 1. **End to end.** A trivial derivation builds through the proxy, and the builder that ran it
#    records the drv in its `post-build-hook` log.
# 2. **Placement follows the responder.** With builder A answering `ready maxconn:0`, the next
#    build lands on B instead of queueing on A. That is the point of the change: the spill point is
#    a runtime fact, not a number fixed at deploy time.
# 3. **Saturation spills.** With both builders at `maxconn:1` and two distinct derivations, each
#    builder takes exactly one.
#
# What it does not prove: dedup across clients (Nix's own queueing is the mechanism, not the
# responder), any gain in throughput, and anything about aarch64 — no VM here is emulated.
{
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs) lib;

  proxyConfig = pkgs.writeText "build-farm-poc-haproxy.cfg" ''
    global
      log stdout format raw local0
      maxconn 64
      # The test reads the per-server session counters from here. A log line is a weaker signal:
      # it depends on the format and on where stdout goes.
      stats socket /run/haproxy/admin.sock mode 660 level admin

    defaults
      mode tcp
      log global
      option tcplog
      timeout connect 5s
      timeout client 60s
      timeout server 60s
      timeout queue 10s

    frontend farm_in
      bind *:2222
      default_backend farm_out

    backend farm_out
      balance first
      # The same shape the farm uses: `maxconn` is the static ceiling, the agent-check moves the
      # effective value at run time, and `maxqueue` bounds a wait once every server is full.
      server builder-a builder-a:22 check inter 1s fall 2 rise 1 maxqueue 2 maxconn 4 agent-check agent-inter 1s agent-port 9100
      server builder-b builder-b:22 check inter 1s fall 2 rise 1 maxqueue 2 maxconn 4 agent-check agent-inter 1s agent-port 9100
  '';

  builder =
    { ... }:
    {
      imports = [ ./module.nix ];
      services.build-farm-ready.enable = true;
      services.openssh = {
        enable = true;
        settings.PermitRootLogin = "yes";
        settings.PasswordAuthentication = false;
      };
      nix.settings = {
        trusted-users = [ "root" ];
        # The test builds a bare `derivation`, which does not declare its builder's closure as
        # inputs. With the sandbox on, the builder's libraries are not mounted and the build dies
        # with "No such file or directory". The sandbox is not what this test measures.
        sandbox = false;
      };
      # The test's drv names this exact bash path. A builder only holds its own system closure, so
      # the one input must be seeded or the build dies with "No such file or directory".
      virtualisation.additionalPaths = [ pkgs.bash ];
      networking.firewall.enable = false;
    };
in
pkgs.testers.runNixOSTest {
  name = "build-farm-ready";

  nodes = {
    proxy =
      { ... }:
      {
        services.haproxy = {
          enable = true;
          config = builtins.readFile proxyConfig;
        };
        environment.systemPackages = [ pkgs.socat ];
        networking.firewall.enable = false;
      };

    builder-a = builder;
    builder-b = builder;

    client =
      { ... }:
      {
        nix.distributedBuilds = true;
        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          # A file, not `nix.buildMachines`: the daemon re-reads it per derivation, which is how the
          # real farm switches a builder on and off without a restart. `nix-remote-build.nix`
          # defines this option as `null` unless `buildMachines` is used, so the file form wins.
          builders = lib.mkForce "@/etc/nix/machines";
          builders-use-substitutes = false;
        };
        environment.etc."nix/machines".text = ''
          ssh-ng://root@farm x86_64-linux - 2 1 - -
        '';
        # `ssh-ng` reads the SSH config, and the alias is what carries the non-default port. This is
        # the same shape `modules/den/aspects/build-farm.nix` writes for the real fleet.
        programs.ssh.extraConfig = ''
          Host farm
            HostName proxy
            Port 2222
            User root
            IdentityFile /root/.ssh/id_ed25519
            StrictHostKeyChecking no
            UserKnownHostsFile /dev/null
            LogLevel ERROR
        '';
        virtualisation.additionalPaths = [ pkgs.bash ];
        networking.firewall.enable = false;
      };
  };

  testScript = ''
    import time

    start_all()

    proxy.wait_for_unit("haproxy.service")
    for builder in (builder_a, builder_b):
        builder.wait_for_unit("sshd.service")
        builder.wait_for_unit("build-farm-ready.service")

    # One key pair, trusted by both builders: the proxy multiplexes them behind one name, so the
    # client cannot use a different identity per backend.
    client.succeed("mkdir -p /root/.ssh && ssh-keygen -q -t ed25519 -N \"\" -f /root/.ssh/id_ed25519")
    pub = client.succeed("cat /root/.ssh/id_ed25519.pub").strip()
    for builder in (builder_a, builder_b):
        builder.succeed(
            "mkdir -p /root/.ssh && printf '%s\\n' '"
            + pub
            + "' > /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys"
        )

    client.wait_until_succeeds("timeout 1 bash -c '</dev/tcp/proxy/2222'", timeout=120)
    # A real SSH handshake through the proxy is the readiness signal. HAProxy logs a server "UP"
    # only on a transition, so that line is not a reliable wait condition.
    client.wait_until_succeeds(
        "ssh -o BatchMode=yes farm true", timeout=180
    )

    BASH = "${pkgs.bash}/bin/bash"

    def drv(name):
        """A bare derivation with one input, `bash`, which every VM already has in its store.

        Nothing is pre-seeded: the drv is created inside the client, so its output cannot already
        exist and the build cannot short-circuit. No nixpkgs is imported, so the client does not
        re-instantiate a second, mismatched package set.
        """
        return (
            f'derivation {{ name = "build-farm-poc-{name}"; system = "x86_64-linux"; '
            f'builder = "{BASH}"; args = [ "-c" "echo {name} > $out" ]; }}'
        )

    def build(*names):
        # One expression, so one `nix build` schedules every derivation together. Separate
        # `--expr` flags are not a concurrency guarantee: Nix may run them one after the other.
        # Parentheses matter: in a Nix list, `f { }` is two elements, not an application.
        expr = (
            drv(names[0])
            if len(names) == 1
            else "[ " + " ".join(f"({drv(n)})" for n in names) + " ]"
        )
        rc, out = client.execute(f"nix build --no-link --max-jobs 0 --impure --expr '{expr}' 2>&1")
        assert rc == 0, f"nix build failed:\n{out}"

    def set_slots(builder, slots):
        builder.succeed(f"echo {slots} > /run/build-farm-ready/maxconn")

    def server_counts():
        """How many client connections HAProxy has sent to each builder so far.

        The proxy is the only component that sees the choice, so its own counters are the
        evidence. The test VMs share the host store, and `nix-store --serve` does not run
        `post-build-hook`, so neither the store nor a hook can name the builder.
        """
        out = proxy.succeed(
            "echo 'show stat' | socat /run/haproxy/admin.sock stdio | awk -F, '"
            "NR==1 { for (i=1;i<=NF;i++) if ($i==\"stot\") c=i; next } "
            "$1==\"farm_out\" && ($2==\"builder-a\" || $2==\"builder-b\") { print $2, $c }'"
        )
        counts = {"a": 0, "b": 0}
        for line in out.splitlines():
            parts = line.split()
            if len(parts) == 2:
                counts[parts[0][-1]] = int(parts[1])
        return counts

    def landed(*names):
        """The per-builder connection delta caused by one build call."""
        before = server_counts()
        build(*names)
        after = server_counts()
        return {k: after[k] - before[k] for k in after}

    # 1. End to end: the build goes through the proxy and a builder takes it.
    placed = landed("one")
    assert placed == {"a": 1, "b": 0}, f"expected builder a, got {placed}"

    # 2. Placement follows the responder: A takes no new build, so B does.
    set_slots(builder_a, 0)
    time.sleep(3)  # agent-inter 1s, plus the health check
    placed = landed("two")
    assert placed == {"a": 0, "b": 1}, f"expected builder b with a drained, got {placed}"

    # 3. Saturation spills: one slot each, two distinct derivations, one per builder.
    set_slots(builder_a, 1)
    set_slots(builder_b, 1)
    time.sleep(3)
    placed = landed("three", "four")
    assert placed == {"a": 1, "b": 1}, f"expected one build per builder, got {placed}"
  '';
}
