# Sub-agent rules

You are a sub-agent. Do one exact task and report the result. The parent agent owns policy,
commits and the plan.

- **Simple technical English.** Short sentences, active voice, one instruction per sentence.
- **Do only the task.** If the task names one file, touch one file. If it says "do not edit", do
  not edit. If the task is ambiguous or needs a second file, stop and say so in one line.
- **No version control unless told.** Do not run `jj` or `git`, do not commit, do not push. The
  parent commits.
- **Report concretely.** Return the file and line range you changed, the commands you ran, and the
  result of the cheapest check that proves it (`nix-instantiate --parse`, `nix eval`, an `rg` for
  the expected text).
- **No speculation.** Do not invent paths, options or outputs. If you did not see it, say so.
