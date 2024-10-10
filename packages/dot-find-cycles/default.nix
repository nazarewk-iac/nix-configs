{ pkgs, lib, ... }:
# see https://github.com/systemd/systemd/issues/3829#issuecomment-327773498
# see https://github.com/jantman/misc-scripts/blob/master/dot_find_cycles.py
pkgs.writers.writePython3Bin "dot-find-cycles"
{
  libraries = with pkgs.python3Packages; [
    decorator
    graphviz
    networkx
    pydot
    pyparsing
  ];
  doCheck = false;
}
  (pkgs.fetchurl {
    url = "https://github.com/jantman/misc-scripts/raw/1ef3d280b399071587f66c9dad50b8ce5b134845/dot_find_cycles.py";
    hash = "sha256-7K5RvUul/xEH81o0q9Y9WQQnCpXH8HklkecY/tGL1Zk=";
  })
