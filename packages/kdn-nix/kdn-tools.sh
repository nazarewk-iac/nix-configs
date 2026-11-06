#!/usr/bin/env bash
set -Eeuo pipefail

# kdn-tools is a curated reminder of the custom tooling this repository provides.
# Keep this list in step with packages/. The authoritative, described list is
# `nix flake show packages`.
cat <<'LIST'
Nix maintenance (packages/kdn-nix):
  kdn-nix-collect-garbage   bounded GC: -c/--batch-count N, -s/--batch-size 2G; --verify opt-in
  kdn-nix-reap-builders     plan|apply: reap leaked nix-daemon temp-root workers (apply reads a saved plan)
  kdn-nix-list-roots        print GC roots
  kdn-nix-which             resolve a command/attr to its store path
  kdn-tools                 this listing

LLM / agent helpers (packages/llm):
  zellij-llm                run+watch long commands and OpenCode/Pi panes in a dedicated zellij session
  kdn-slug                  naming convention for zellij session/tab/pane
  llm-stats                 llama-swap per-request performance stats

Pi extensions in use (~/.pi/agent/extensions):
  idle-marker               writes $PI_IDLE_MARKER (running/idle/aborted) on agent_settled
  timestamps                appends a non-context [HH:MM:SS] line above each message
  subagent                  delegate to scout/worker/reviewer/planner; per-task `model` override,
                            $PI_SUBAGENT_LOG and $PI_SUBAGENT_SESSIONS

Repository packages (packages/):
  nix / deploy:   kdn-nix  kdn-nix-fmt  kdn-nix-bootstrap  kdn-cidata-iso  flake-lock-merge  darwin-rebuild
  certs/secrets:  kdn-certs  kdn-anonymize  pass-secret-service  kdn-keepass  pinentry
  ssh / yubi:     kdn-ssh-access  kdn-yk  gpg-smartcard-reset-keys  git-credential-keyring
  infra / agents: kdnctl  jj-mcp  mcpsnoop  opencode-compat-proxy  basic-memory  aws-sso  kagi-cli
  storage / zfs:  kdn-disko-zfs  spec|show|plan|apply a host's disko-declared ZFS datasets
                  (wraps numtide/disko-zfs; auto-ignores undeclared live datasets, so
                  plan never proposes destroying container/volume storage)
  desktop / sys:  sway-vnc  systemd-cryptsetup  systemd-find-cycles  kdn-gamingctl  rambox  lnav
  dev / misc:     link-python  init-py-script  git-utils  klg  klog-time-tracker  data-converters
                  ff-ctl  fortitoken-decrypt  ss-util  tc-redirect-tap  whicher  ik-llama-cpp
  llama.cpp:      (packages/llama-cpp) custom llama.cpp builds used by the fleet
  netbird:        (packages/netbird) netbird  netbird-dashboard  netbird-management
                  netbird-relay  netbird-signal  netbird-ui  netbird-upload

Authoritative list with descriptions:
  nix flake show packages
  ls packages/ packages/llm/ packages/netbird/
LIST
