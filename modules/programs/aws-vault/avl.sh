function avl() {
  local profiles p
  if [ "${#@}" = 0 ]; then
    profiles=($(aws-vault list --profiles))
  else
    profiles=("$@")
  fi
  for p in "${profiles[@]}"; do
    echo "Logging in to $p..." >&2
    aws-vault exec "$p" -- bash -c 'echo "Successfully logged in to $p" >&2'
  done
}
