# aws-sso

CLI tool for managing AWS SSO sessions: listing accounts/roles, generating `~/.aws/config` profiles, and registering EKS clusters into kubeconfig.

Tokens are refreshed automatically via `aws sso login` when less than 1 minute remains before expiry.

> All examples use `nix run '.#aws-sso' --`. If the package is installed, replace that with `aws-sso`.

```shell
nix run '.#aws-sso' -- --help
nix run '.#aws-sso' -- [--session <name>] [--region <region>] list
nix run '.#aws-sso' -- [--session <name>] [--region <region>] generate-profiles [--prefix <prefix>]
nix run '.#aws-sso' -- [--session <name>] [--region <region>] generate-kubeconfig [--prefix <prefix>] [--role-pattern <regex>] [--eks-region <region>]
```

## Commands

### `list`

List all SSO accounts and their roles.

```shell
nix run '.#aws-sso' -- --session myorg list
```

### `generate-profiles`

Write all account/role combinations as `[profile ...]` stanzas into `~/.aws/config` (or `$AWS_CONFIG_FILE`).
The managed block is delimited by `# BEGIN aws-sso-managed` / `# END aws-sso-managed` markers and replaced on each run.

Profile names follow the pattern: `{prefix}-{account_name}--{role}--{account_id}` (kebab-cased).

```shell
nix run '.#aws-sso' -- --session myorg generate-profiles --prefix myorg
```

### `generate-kubeconfig`

For each role matching `--role-pattern`, fetch temporary credentials, list EKS clusters, and register them via `aws eks update-kubeconfig`.

Each cluster gets two kubeconfig contexts:
- **Full**: `{prefix}-{account_name}--{cluster}--{account_id}` — unambiguous, safe when multiple accounts have same-named clusters
- **Short**: `{prefix}--{cluster}` — ergonomic alias pointing at the same credentials

```shell
nix run '.#aws-sso' -- --session myorg generate-kubeconfig \
  --prefix myorg \
  --role-pattern ".*-kubernetes" \
  --eks-region us-east-1
```

## Global flags

| Flag | Default | Description |
|---|---|---|
| `--session` | none | SSO session name from `~/.aws/config` `[sso-session ...]` |
| `--region` | read from session config, else `us-east-1` | SSO API region |

## Dev environment

To build a Python interpreter/virtualenv for your IDE:

```shell
nix run '.#link-python' -- aws-sso
```
