Future purpose-built design idea (without `sops-nix`)

1. react to sops file change in a folder (watchexec)
    - simply decrypt a file & convert to JSON accessible only to root
      - eg: `/etc/kdn/secrets/<name>/<version>.sops.yaml` -> `/run/kdn/secrets/decrypted/<name>/<version>.json`
      - `<unit>-decrypted@<name>-<version>.service`
      - `<unit>-decrypted@<name>-<version>.target`
    - by default linked from store
    - could utilize script for pulling in new versions
    - named files
2. on-decryption:
    - in a systemd.service/target
    - render files structure like I did with `sops-nix` to `*.N` folder and symlink back
    - change ownership & permissions
    - partial render
    - render a template based on the JSON file
    - create target files and allow them to fail when unavailable
3. a tool to search for value across multiple decrypted SOPS json files
   - construct a single JSON output to be used as templates context?
4. template rendering
    