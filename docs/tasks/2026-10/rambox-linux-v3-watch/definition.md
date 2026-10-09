---
type: Task
description: Add a periodic check that reports when Rambox publishes a Linux x64 AppImage for a v3+ release, so packages/rambox can be bumped.
status: open
authored_by: agent
timestamp: 2026-10-09T21:28:03+02:00
---

# Watch for a Rambox v3+ Linux release

## Background

`packages/rambox/default.nix` holds `pkgs.kdn.rambox`, a copy of the nixpkgs
`pkgs/by-name/ra/rambox/package.nix` definition. The package wraps an upstream
Linux x64 AppImage. It is pinned to **2.7.1**, the newest stable Linux release
at the time of writing (2026-10-09). The pinned nixpkgs build is older, 2.6.3.

Rambox ships the Linux AppImage **after** the macOS and Windows builds. The
newest release overall, **3.1.0** (2026-10-07), has no Linux asset. Its assets
are only `Rambox-3.1.0-mac.dmg`, `Rambox-3.1.0-mac.zip` and
`Rambox-3.1.0-win-x64.exe`. Its release notes say:

> Linux: We are working to provide the installers ASAP.

The newest release with any Linux asset is **2.7.2-beta.1** (a beta). The newest
stable Linux release is **2.7.1**. So the repository cannot move to v3 yet: the
upstream Linux artifact does not exist.

The package only supports Linux (`platforms = [ "x86_64-linux" ]`), and it
tracks the Linux AppImage alone.

## Goal

Detect a v3+ Linux x64 AppImage as soon as upstream publishes one, without a
manual check. When the check fires, the bump is one edit to
`packages/rambox/default.nix`: set `version`, then set the `hash` from a
prefetch.

## Proposed approach

Add a scheduled check. It runs at least once a week and reports a hit.

1. Read `https://api.github.com/repos/ramboxapp/download/releases?per_page=30`.
2. Keep a release when both hold:
   - `tag_name` matches `^v3` (extend to `^v[3-9]` for later majors), and
   - one asset name matches `^Rambox-.*-linux-x64\.AppImage$`.
3. Report the tag and the asset `browser_download_url`.

Two candidate homes for the check:

- **A GitHub Actions scheduled workflow** in this repository. It does not need a
  host to be online. It can open or update a tracking issue.
- **A systemd timer plus a small script** on a host that runs Rambox (oams). It
  is simpler to run locally, but it needs the host to be up.

The unauthenticated GitHub API allows 60 requests per hour, so one request per
day or per week is safe. Use the `nix/access-tokens/github.com` token if the
check needs a higher limit.

## Acceptance criteria

- A scheduled mechanism runs at least weekly.
- On a v3+ Linux AppImage it reports the tag and the download URL.
- The report leads to one documented bump step for
  `packages/rambox/default.nix` (`version` and `hash`).

## Open questions

- Where should the check live: a GitHub Actions workflow, or a host timer?
- Do beta and pre-release v3 builds count, or only stable releases?
- Which notification channel: a GitHub issue, a local notification, or another
  service?

## References

- [packages/rambox/default.nix](../../../../packages/rambox/default.nix) — the
  package and the fields to bump.
- [hosts/oams/default.nix](../../../../hosts/oams/default.nix) — the host that
  selects `pkgs.kdn.rambox`.
- [docs/tasks/2026-10/llama-cpp-latest-package/definition.md](../llama-cpp-latest-package/definition.md)
  — a similar in-repo package that tracks an upstream release.
- GitHub releases API:
  <https://api.github.com/repos/ramboxapp/download/releases>.
- Rambox 3.1.0 release (no Linux asset, notes the Linux delay):
  <https://github.com/ramboxapp/download/releases/tag/v3.1.0>.
- nixpkgs base definition:
  `pkgs/by-name/ra/rambox/package.nix`.
