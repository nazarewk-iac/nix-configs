# kdn-signing — print the shell lines that select a git and jj signing route.
#
# A child process cannot change the environment of its parent. So this script prints lines and
# the caller runs them. That is the whole design.
#
#   eval "$(kdn-signing plain)"          # bash, zsh
#   kdn-signing plain fish | source      # fish
#
# Every line the script writes to stdout is either a comment or a variable assignment, so an
# `eval` of any route is safe.

usage() {
  cat <<'EOF'
kdn-signing — print the shell lines that select a git and jj signing route.

Usage:
  kdn-signing <route> [<shell>]

Routes:
  plain    sign with a plain ssh-keygen key
           (sets GIT_CONFIG_GLOBAL, JJ_CONFIG and GIT_SSH_COMMAND)
  default  return to the activated configuration (unsets the three variables)
  status   print the current values, as comments

Shell:
  fish   | --shell=fish     `set -gx` and `set -e`
  bash   | --shell=bash     `export` and `unset`; also correct for zsh and dash
  The default comes from $SHELL. Every shell other than fish gets the `export` syntax.

Examples:
  eval "$(kdn-signing plain)"
  kdn-signing plain fish | source
  kdn-signing status
EOF
}

route=""
shell_kind=""

for arg in "$@"; do
  case "$arg" in
  plain | default | status) route="$arg" ;;
  1p) route=default ;;
  fish | bash | zsh | posix) shell_kind="$arg" ;;
  --shell=*) shell_kind="${arg#--shell=}" ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'kdn-signing: unknown argument: %s\n' "$arg" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if test -z "$route"; then
  printf 'kdn-signing: name a route: plain, default or status\n' >&2
  usage >&2
  exit 2
fi

if test -z "$shell_kind"; then
  case "${SHELL:-}" in
  */fish) shell_kind=fish ;;
  *) shell_kind=bash ;;
  esac
fi

case "$shell_kind" in
fish | bash | zsh | posix) ;;
*)
  printf 'kdn-signing: unknown shell: %s\n' "$shell_kind" >&2
  exit 2
  ;;
esac

# $2 arrives with its own quotes, so a value keeps the quote style the route needs.
emit_set() {
  case "$shell_kind" in
  fish) printf 'set -gx %s %s\n' "$1" "$2" ;;
  *) printf 'export %s=%s\n' "$1" "$2" ;;
  esac
}

emit_unset() {
  case "$shell_kind" in
  fish) printf 'set -e %s\n' "$1" ;;
  *) printf 'unset %s\n' "$1" ;;
  esac
}

case "$route" in
plain)
  if ! test -f "$KDN_SIGNING_PLAIN_KEY"; then
    printf 'kdn-signing: the plain key is missing: %s\n' "$KDN_SIGNING_PLAIN_KEY" >&2
    printf 'kdn-signing: create it, then run this route again:\n' >&2
    printf "  ssh-keygen -t ed25519 -C 'plain signing key' -f %s\n" "$KDN_SIGNING_PLAIN_KEY" >&2
    printf 'kdn-signing: register the public key on the git host as a SIGNING key.\n' >&2
    exit 1
  fi
  printf '# kdn-signing: route=plain key=%s\n' "$KDN_SIGNING_PLAIN_KEY"
  emit_set GIT_CONFIG_GLOBAL "'$KDN_SIGNING_GIT_PLAIN'"
  emit_set JJ_CONFIG "'$KDN_SIGNING_JJ_BASE:$KDN_SIGNING_JJ_PLAIN'"
  # The caller's shell expands $SSH_AUTH_SOCK, so the value follows a later agent restart.
  # A command-line `-o` beats every ssh_config file, which is the point of this line.
  # shellcheck disable=SC2016 # the caller expands the variable, not this script
  emit_set GIT_SSH_COMMAND '"ssh -o IdentityAgent=$SSH_AUTH_SOCK"'
  ;;
default)
  printf '# kdn-signing: route=default (the activated configuration)\n'
  emit_unset GIT_CONFIG_GLOBAL
  emit_unset JJ_CONFIG
  emit_unset GIT_SSH_COMMAND
  ;;
status)
  printf '# kdn-signing: GIT_CONFIG_GLOBAL=%s\n' "${GIT_CONFIG_GLOBAL:-<unset>}"
  printf '# kdn-signing: JJ_CONFIG=%s\n' "${JJ_CONFIG:-<unset>}"
  printf '# kdn-signing: GIT_SSH_COMMAND=%s\n' "${GIT_SSH_COMMAND:-<unset>}"
  printf '# kdn-signing: allowed_signers=%s\n' "$KDN_SIGNING_ALLOWED_SIGNERS"
  printf '# kdn-signing: plain key=%s\n' "$KDN_SIGNING_PLAIN_KEY"
  if test -f "$KDN_SIGNING_PLAIN_KEY"; then
    printf '# kdn-signing: the plain key exists\n'
  else
    printf '# kdn-signing: the plain key is missing\n'
  fi
  ;;
esac
