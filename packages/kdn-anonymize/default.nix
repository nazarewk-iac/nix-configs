{pkgs}: pkgs.writers.writePython3Bin "kdn-anonymize" {} (builtins.readFile ./kdn-anonymize.py)
