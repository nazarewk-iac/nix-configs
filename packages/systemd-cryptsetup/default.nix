{
  runCommand,
  systemd,
  ...
}:
runCommand "systemd-cryptsetup" {
  meta.mainProgram = "systemd-cryptsetup";
} ''
  mkdir -p $out/bin
  ln -sf ${systemd}/lib/systemd/systemd-cryptsetup $out/bin/
''
