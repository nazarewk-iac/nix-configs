#!/usr/bin/env bash
# Completion check for one fork flake update.
#
# The check is read-only. It runs every assertion, then exits 1 when any assertion fails.
# Run it at the end of the update, before the hand-off to the user.
#
# Why the check is mandatory: an incomplete run looks finished. The two chain tips already
# differ even when the public chain holds no update at all. Assertion 6 is the one that
# catches that state.
#
# Remote names come from the jj config, so this file holds no remote name.
#   FORK — the private remote, from `git.push` (the fork slot sets it).
#   PUB  — the public remote, from `git.fetch` minus FORK; override with KDN_PUBLIC_REMOTE.
set -uo pipefail

FORK="${KDN_FORK_REMOTE:-$(jj config get git.push 2>/dev/null)}"
if [ -z "$FORK" ]; then
  echo 'FAIL  cannot find the fork remote — set KDN_FORK_REMOTE, or enable the kdn.jj.fork slot' >&2
  exit 1
fi
# The fork slot sets `git.fetch` to both remotes, so the public one is the entry that is not
# FORK. `jj config get` prints a TOML list, so strip the brackets and the quotes first. The slot
# normally sets KDN_PUBLIC_REMOTE through runtimeEnv; this route serves a direct `bash` call.
PUB="${KDN_PUBLIC_REMOTE:-}"
if [ -z "$PUB" ]; then
  PUB="$(jj config get git.fetch 2>/dev/null | tr -d '[]" ' | tr ',' '\n' | grep -vxF "$FORK" | head -1)"
fi
if [ -z "$PUB" ]; then
  echo 'FAIL  cannot find the public remote — set KDN_PUBLIC_REMOTE' >&2
  exit 1
fi

# A shared jq prelude for the two lock-structure assertions.
#
# `res` resolves one input value to a node key. A string value IS the node key. An array value
# is a follows path from the ROOT node, not a node key — so walk it: each element indexes the
# current node's inputs, and that value resolves again. A check that reads `.[0]` of the array
# as a node key reports a false dangling edge on every `["nixpkgs-lib"]` style follows.
# shellcheck disable=SC2016  # $n and $root are jq variables, not shell variables
LOCK_JQ='
def res($n; $root; $v):
  if $v == null then "«missing»"
  elif ($v | type) == "string" then $v
  else reduce $v[] as $seg ($root; res($n; $root; ($n[.].inputs // {})[$seg]))
  end;
def edges($n; $root; $k):
  ($n[$k].inputs // {}) | [to_entries[] | res($n; $root; .value)];
'

fail=0
ck() { if [ "$2" = pass ]; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
nz() { [ -n "$(jj log -r "$1" --no-graph -T '"x"' 2>/dev/null)" ]; }

ft=$(jj log -r 'fork-tip' --no-graph -T 'change_id.short()' 2>/dev/null)
ut=$(jj log -r 'upstream-tip' --no-graph -T 'change_id.short()' 2>/dev/null)
tm=$(jj log -r 'tree-merge' --no-graph -T 'change_id.short()' 2>/dev/null)
echo "fork-tip=$ft  upstream-tip=$ut  tree-merge=$tm"

# 1. two commits exist, one per chain. This alone proves nothing — see the header.
{ [ -n "$ft" ] && [ -n "$ut" ] && [ "$ft" != "$ut" ]; } && r=pass || r=fail
ck "two tips, one per chain, and they differ" "$r"

# 2. the tree merge is a merge with exactly two parents.
#
#    Test the MERGE, never `fork-tip`. A fork-only fix legitimately sits above the merge, and
#    `fork-tip` is then that leaf, not the merge. The docs state the same rule for the insert:
#    `-B tree-merge`, never `-B fork-tip`.
[ "$(jj log -r 'tree-merge' --no-graph -T 'parents.len()' 2>/dev/null)" = 2 ] && r=pass || r=fail
ck "the tree merge has two parents" "$r"

# 3. one parent is the upstream tip. An ancestor is not enough — the link is the point of
#    the shape.
nz 'parents(tree-merge) & upstream-tip' && r=pass || r=fail
ck "the upstream tip is a parent of the tree merge" "$r"

# 3b. the fork chain carries the merge: the fork tip is the merge itself, or a descendant of it.
#     `tree-merge::` includes the merge, so one revset covers both cases.
nz 'fork-tip & tree-merge::' && r=pass || r=fail
ck "the fork tip is the tree merge or a descendant of it" "$r"

# 4. the published fork main stays an ancestor, so the fork push is a fast-forward
nz "main@$FORK & ::fork-tip" && r=pass || r=fail
ck "the published fork main stays an ancestor of the fork tip" "$r"

# 5. the published public main stays an ancestor, so the public push is a fast-forward
nz "main@$PUB & ::upstream-tip" && r=pass || r=fail
ck "the published public main stays an ancestor of the upstream tip" "$r"

# 6. the upstream commit really changed both locks. Run this BEFORE assertion 7: with no
#    upstream commit, assertion 7 counts 0 fork-only nodes and passes for the wrong reason.
for f in flake.lock devenv.lock; do
  if jj file show -r 'upstream-tip' "$f" 2>/dev/null | cmp -s - <(git show "refs/remotes/$PUB/main:$f" 2>/dev/null); then
    r=fail
  else
    r=pass
  fi
  ck "$f on the upstream tip differs from the public remote" "$r"
done

# 7. no fork-only lock node in the upstream commit. This is the structural leak gate, and it
#    needs no pattern list. A pattern check cannot replace it: the current list does not match
#    lock content at all.
for f in flake.lock devenv.lock; do
  n=$(comm -12 \
    <(jj file show -r 'upstream-tip' "$f" 2>/dev/null | jq -r '.nodes|keys[]' | sort) \
    <(comm -23 <(jj file show -r 'fork-tip' "$f" 2>/dev/null | jq -r '.nodes|keys[]' | sort) \
      <(git show "refs/remotes/$PUB/main:$f" 2>/dev/null | jq -r '.nodes|keys[]' | sort)) |
    wc -l | tr -d ' ')
  [ "$n" = 0 ] && r=pass || r=fail
  ck "$f on the upstream tip holds no fork-only node ($n found)" "$r"
done

# 8. no dangling input edge in either lock of the upstream commit. A strip that drops a node
#    but keeps an edge to it makes the lock unresolvable.
for f in flake.lock devenv.lock; do
  d=$(jj file show -r 'upstream-tip' "$f" 2>/dev/null | jq -r "$LOCK_JQ"'
    .nodes as $n | .root as $root
    | [ $n | keys[] as $k | edges($n; $root; $k)[] | select($n[.] == null) ] | length')
  [ "${d:-1}" = 0 ] && r=pass || r=fail
  ck "$f on the upstream tip has no dangling input edge ($d found)" "$r"
done

# 9. no node carries `"inputs": null`. `resolve-lock.nix` reads `node.inputs or { }`, and the
#    `or` operator answers a missing attribute only — never null. A node with no inputs must
#    OMIT the key. A native lock file never writes null here; only a bad strip does.
for rev in upstream-tip fork-tip; do
  for f in flake.lock devenv.lock; do
    n=$(jj file show -r "$rev" "$f" 2>/dev/null |
      jq -r '[.nodes|to_entries[]|select(.value.inputs == null and (.value|has("inputs")))]|length')
    [ "${n:-1}" = 0 ] && r=pass || r=fail
    ck "$f on $rev holds no \"inputs\": null ($n found)" "$r"
  done
done

# 10. every node is reachable from the root. Assertion 8 cannot catch a stripped sub-node that
#     nothing references any more; this one can.
for f in flake.lock devenv.lock; do
  u=$(jj file show -r 'upstream-tip' "$f" 2>/dev/null | jq -r "$LOCK_JQ"'
    .nodes as $n | .root as $root
    | def expand($s): ($s + ([$s[] | edges($n; $root; .)] | add // [])) | unique;
      ([$root] | until(expand(.) == .; expand(.))) as $reached
    | (($n | keys) - $reached) | length')
  [ "${u:-1}" = 0 ] && r=pass || r=fail
  ck "$f on the upstream tip has no unreachable node ($u found)" "$r"
done

# 11. @ is empty with a single parent
[ "$(jj log -r '@' --no-graph -T 'if(empty,"empty","content") ++ " " ++ parents.len()' 2>/dev/null)" = "empty 1" ] && r=pass || r=fail
ck "@ is empty with one parent" "$r"

# 12. no fork content below the upstream tip
nz 'fork-leaked & ::upstream-tip' && r=fail || r=pass
ck "no fork-leaked commit is an ancestor of the upstream tip" "$r"

# A second net, never the gate. `jj fork-audit` greps the file CONTENT at a revision, so it
# catches a private string that assertion 7 cannot see. It reads its own baked pattern list,
# so the operator never types or prints a private string. Always pass `-q` and an explicit
# revset: with no revset it scans both chains and exits 1 as its normal state.
if command -v jj >/dev/null 2>&1; then
  if jj fork-audit -q --color=never 'upstream-tip' >/dev/null 2>&1; then
    echo 'PASS  fork-audit found no denied pattern in the upstream chain (second net, not the gate)'
  else
    echo 'WARN  fork-audit reported a denied pattern in the upstream chain — read its output:'
    jj fork-audit -q --color=never 'upstream-tip'
  fi
fi

exit "$fail"
