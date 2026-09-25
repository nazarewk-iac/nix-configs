# The `ssh-ca` aspect. It turns a CA into an SSH certificate authority and wires the trust on both
# sides of a connection.
#
# ## What it does
#
# It reads two declarations the consumer already made:
#
#   - the SSH CA: one `kdn.ca-dag.cas.<name>` node with `ssh = true`;
#   - the host certificate: one `kdn.certificates.certs.<name>` leaf with `type = "ssh-host"`.
#
# From them it writes the server trust and the client trust.
#
# | Side | Directive | Where |
# |---|---|---|
# | server | `TrustedUserCAKeys` | `services.openssh.settings` on `nixos`, `services.openssh.extraConfig` on `darwin` |
# | server | `HostCertificate` | the same two options |
# | client | `@cert-authority` | a managed `known_hosts` fragment, named by `UserKnownHostsFile` |
# | client | `CertificateFile` | `~/.ssh/config.d/50-kdn-ssh-ca.config` |
#
# ## The CA public key
#
# The CA stores an X.509 certificate (`kdn.ca-dag.cas.<name>.certFile`), and SSH needs the SSH wire
# form of its public key. So the aspect derives the SSH form: `openssl x509 -pubkey` then
# `ssh-keygen -i -m PKCS8`. The derivation runs for the host platform only, so it needs no foreign
# builder. See design § 8.5.
#
# The CA certificate path is `<repoRoot>/<directory>/<certFile>`. The CA DAG declares no path of its
# own, so the aspect reads `kdn.certificates.repoRoot` — the same root the leaf `certPath` uses. A
# consumer that declares an SSH CA names that root, whether or not it also declares a leaf.
#
# ## The classes
#
# `nixos`, `darwin` and `homeManager`. The server half is the first two; the client half is the
# third. An empty `kdn.ca-dag.cas` and an empty `kdn.certificates.certs` are the no-op, so inclusion
# alone changes nothing.
#
# ## The client drop-in
#
# The file is `~/.ssh/config.d/50-kdn-ssh-ca.config`. `program-ssh-client` includes that directory
# through `programs.ssh.includes`, and `ssh-access` writes `40-kdn-ssh-access.config` into the same
# directory. The `50-` number sorts this file after the `40-` file.
#
# `@cert-authority` belongs in a `known_hosts` file, and the live `~/.ssh/known_hosts` is not a store
# path: `ssh` appends to it at run time. So the aspect writes a managed fragment and names it in
# `UserKnownHostsFile`, next to the live file.
#
# ## Orthogonality with `kdn-ssh-access`
#
# `kdn-ssh-access` picks routes and identities. It does not decide trust. This aspect decides trust
# only. It reads no `kdn.ssh-access` option, and no `kdn.ssh-access` file reads a `kdn.ssh-ca`
# option.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. An empty CA set and an empty leaf set are the
#    no-op.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  # The client drop-in, and the user certificate it presents.
  dropInPath = ".ssh/config.d/50-kdn-ssh-ca.config";
  userCertPath = "~/.ssh/id_ed25519-cert.pub";

  # The managed `known_hosts` fragment. A store path must not be the live `~/.ssh/known_hosts`,
  # because `ssh` appends to that file at run time.
  knownHostsPath = ".ssh/known_hosts.d/50-kdn-ssh-ca";

  # The SSH public key of a CA, derived from its X.509 certificate. A CA stores a PEM certificate
  # and no SSH key, so the aspect derives the SSH wire form. `ssh-keygen -i -m PKCS8` reads the
  # public key of the certificate, and the result is one `ssh-<type> <base64>` line.
  mkSshCaPubKey =
    pkgs: certFile:
    pkgs.runCommand "kdn-ssh-ca.pub"
      {
        nativeBuildInputs = [
          pkgs.openssl
          pkgs.openssh
        ];
      }
      ''
        openssl x509 -in ${certFile} -pubkey -noout \
          | ssh-keygen -i -m PKCS8 -f /dev/stdin > $out
      '';

  # The managed `known_hosts` fragment. `@cert-authority *` trusts every host certificate the CA
  # signs, exactly as design § 7.2 states.
  mkKnownHosts =
    pkgs: caPubFile:
    pkgs.runCommand "kdn-ssh-ca-known-hosts" { } ''
      printf '@cert-authority * ' > $out
      cat ${caPubFile} >> $out
    '';

  # The two server directives, as `sshd_config` text. The `nixos` class passes them through the
  # `services.openssh.settings` option; the `darwin` class writes them through
  # `services.openssh.extraConfig`.
  serverDirectives = caPubFile: hostCertPath: ''
    TrustedUserCAKeys ${caPubFile}
    HostCertificate ${hostCertPath}
  '';

  # The SSH CA of one target: the first CA with `ssh = true`. `null` when the consumer declares
  # none, which keeps the whole body a no-op.
  findSshCa = cas: lib: lib.findFirst (ca: ca.ssh) null (lib.attrValues cas);

  # The host certificate of one target: the first leaf with `type = "ssh-host"`. `null` when the
  # consumer declares none.
  findHostCert =
    certs: lib: lib.findFirst (cert: cert.type == "ssh-host") null (lib.attrValues certs);

  # The repository root the consumer names. The CA DAG declares a repo-relative directory and a
  # filename, so the aspect joins them onto this root. A declared SSH CA needs the value, so a
  # missing one is a hard error at the one point that reads it.
  repoRootOf =
    config:
    if config.kdn.certificates.repoRoot == null then
      throw "kdn.ssh-ca: set `kdn.certificates.repoRoot` when you declare an SSH CA"
    else
      config.kdn.certificates.repoRoot;

  # The X.509 certificate path of one CA.
  caCertPath = config: ca: "${toString (repoRootOf config)}/${ca.directory}/${ca.certFile}";
in
{
  # The SSH CA reads the CA graph and the leaf set, so it carries both option trees. An import
  # dedupes by path, so a consumer that already includes either aspect pays nothing extra.
  kdn.ssh-ca.includes = [
    kdn.ca-dag
    kdn.certificates
  ];

  # The server half on NixOS. It writes the two directives through the nixpkgs option.
  kdn.ssh-ca.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sshCa = findSshCa config.kdn.ca-dag.cas lib;
      hostCert = findHostCert config.kdn.certificates.certs lib;
    in
    {
      config = lib.mkIf (sshCa != null && hostCert != null) {
        services.openssh.settings = {
          TrustedUserCAKeys = toString (mkSshCaPubKey pkgs (caCertPath config sshCa));
          HostCertificate = toString hostCert.certPath;
        };
      };
    };

  # The server half on nix-darwin. It declares no `services.openssh.settings`, so the two
  # directives go through `services.openssh.extraConfig` as a `sshd_config` fragment. See design
  # § 7.1 and § 7.5.
  kdn.ssh-ca.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sshCa = findSshCa config.kdn.ca-dag.cas lib;
      hostCert = findHostCert config.kdn.certificates.certs lib;
    in
    {
      config = lib.mkIf (sshCa != null && hostCert != null) {
        services.openssh.extraConfig = serverDirectives (mkSshCaPubKey pkgs (caCertPath config sshCa)) hostCert.certPath;
      };
    };

  # The client half. It writes the `CertificateFile` drop-in and the `@cert-authority` fragment,
  # then names the fragment in `UserKnownHostsFile`.
  kdn.ssh-ca.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      sshCa = findSshCa config.kdn.ca-dag.cas lib;
    in
    {
      config = lib.mkIf (sshCa != null) {
        home.file.${dropInPath}.text = ''
          CertificateFile ${userCertPath}
          UserKnownHostsFile ~/.ssh/known_hosts ~/${knownHostsPath}
        '';
        home.file.${knownHostsPath}.source = mkKnownHosts pkgs (
          mkSshCaPubKey pkgs (caCertPath config sshCa)
        );
      };
    };
}
