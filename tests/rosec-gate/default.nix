{ pkgs }:
# NixOS test for the rosec unlock gate: the real gate script, the same unit graph as the module,
# with a stub daemon, a stub `rosec` and a stub `busctl`. It proves the three behaviours the design
# promises: a dependent pulls the unlock, a lock kills the target but not the dependent, and a
# dependent restart re-arms the gate.
let
  gate = pkgs.writeShellApplication {
    name = "rosec-gate";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
      pkgs.gnused
      pkgs.gawk
      pkgs.util-linux
    ];
    text = builtins.readFile ../../modules/universal/services/rosec/rosec-gate.sh;
  };

  rosecStub = pkgs.writeShellScriptBin "rosec" ''
    if [ "''${1:-}" = unlock ]; then
      printf 'No password needed [Press Enter — the age identity unlocks this store]: '
      read -r _
      sleep 1
      echo 46 > /run/gate-test/items
      exit 0
    fi
    exit 1
  '';

  busctlStub = pkgs.writeShellScriptBin "busctl" ''
    case "$*" in
      *"org.rosec.Daemon Status"*)
        printf 'u %s\n' "$(cat /run/gate-test/items 2>/dev/null || echo 0)"
        ;;
      *) exit 1 ;;
    esac
  '';

  stubs = pkgs.symlinkJoin {
    name = "gate-stubs";
    paths = [ rosecStub busctlStub ];
  };

  unlockGate = pkgs.writeShellScriptBin "rosec-unlock-gate" ''
    set -eu
    ${pkgs.expect}/bin/expect -c '
      set timeout 30
      spawn rosec unlock
      expect {
        -re "Press Enter|No password needed" { send "\r"; exp_continue }
        timeout { exit 1 }
        eof
      }
    ' || exit 1
    exec ${gate}/bin/rosec-gate wait "$1"
  '';

  gateEnv = [
    "PATH=${stubs}/bin:${pkgs.systemd}/bin:${pkgs.coreutils}/bin"
    "GATE_SCOPE=system"
    "GATE_STATE_DIR=/run/gate-test/state"
    "GATE_PROBE_TIMEOUT=10"
    "GATE_BUSCTL=${stubs}/bin/busctl"
    "GATE_ROSEC=${stubs}/bin/rosec"
  ];
in
pkgs.testers.runNixOSTest {
  name = "rosec-gate";

  nodes.machine = {
    systemd.services.kdn-secret-service = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };

    systemd.services."secret-service-unlock@" = {
      requires = [ "kdn-secret-service.service" ];
      after = [ "kdn-secret-service.service" ];
      partOf = [ "kdn-secret-service.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "60s";
        Environment = gateEnv;
        ExecStart = "${unlockGate}/bin/rosec-unlock-gate %i";
      };
    };

    systemd.services."secret-service-probe@" = {
      requires = [ "kdn-secret-service.service" ];
      after = [ "kdn-secret-service.service" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "30s";
        Environment = gateEnv;
        ExecStart = "${gate}/bin/rosec-gate probe %i";
      };
    };

    systemd.targets."secret-service-unlocked@" = {
      wants = [ "secret-service-unlock@%i.service" ];
      after = [ "secret-service-unlock@%i.service" ];
      bindsTo = [ "secret-service-unlock@%i.service" ];
      partOf = [ "secret-service-unlock@%i.service" ];
    };

    systemd.services.dependent = {
      wantedBy = [ "multi-user.target" ];
      wants = [ "secret-service-unlocked@sops.target" ];
      after = [ "secret-service-unlocked@sops.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("kdn-secret-service.service")
    machine.succeed("mkdir -p /run/gate-test/state && echo 0 > /run/gate-test/items")

    # 1. a dependent start pulls the target, which pulls the unlock
    machine.succeed("systemctl start dependent.service")
    machine.wait_for_unit("secret-service-unlocked@sops.target")
    machine.succeed("systemctl is-active --quiet dependent.service")
    machine.succeed("grep -q 'state=ready' /run/gate-test/state/sops.state")

    # 2. a lock stops the gate, the dependent survives
    machine.succeed("echo 0 > /run/gate-test/items")
    machine.succeed("systemctl start secret-service-probe@sops.service")
    machine.wait_until_succeeds("! systemctl is-active --quiet secret-service-unlocked@sops.target")
    machine.succeed("systemctl is-active --quiet dependent.service")

    # 3. restarting the dependent re-arms the gate
    machine.succeed("systemctl restart dependent.service")
    machine.wait_for_unit("secret-service-unlocked@sops.target")
    machine.succeed("grep -q 'state=ready' /run/gate-test/state/sops.state")
  '';
}
