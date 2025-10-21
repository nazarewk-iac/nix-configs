{
  lib,
  python3,
  writeShellApplication,
  android-tools,
}:
let
  interpreter = writeShellApplication {
    name = "python";
    runtimeInputs = [
      android-tools
      (python3.withPackages (
        pp: with pp; [
          pycrypto
        ]
      ))
    ];
    text = ''python3 "$@"'';
  };
in
writeShellApplication {
  name = "fortitoken-decrypt";
  derivationArgs.passthru.python = interpreter;
  text = ''${lib.getExe interpreter} ${./fortitoken-decrypt.py}'';
}
