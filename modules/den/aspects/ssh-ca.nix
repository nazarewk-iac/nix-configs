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
# `nixos`, `darwin`, `homeManager` and `devenv`. The server half is the first two; the client half
# is `homeManager`. An empty `kdn.ca-dag.cas` and an empty `kdn.certificates.certs` are the no-op,
# so inclusion alone changes nothing.
#
# The `devenv` class is the operator's shell. It includes `ca-manager`, so a shell that asks for
# `ssh-ca` also holds the `kdn-certs` CLI and the CA DAG. A user who signs a user certificate
# (`kdn-certs ssh login <host>`) and the host that serves it therefore share one aspect. The
# host classes stay inert: a NixOS host reads the DAG data, not the CLI.
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
  # The fleet's per-host SSH identity: the certificate principals and the committed public key of
  # the deployed host key. One source, so a principal list and a pin cannot drift apart.
  fleet = import ../../../data/net/ssh-host-identities.nix;

  # One `known_hosts` entry per fleet host, generated from the committed public key. A host that is
  # missing from the inventory gets no generated pin and keeps whatever its own declaration says.
  fleetKnownHosts = lib: lib.mapAttrs' (
    name: host:
    lib.nameValuePair "kdn-host-${name}" {
      hostNames = host.names;
      publicKeyFile = host.publicKeyFile;
    }
  ) fleet;

  # Declared in every class: a consumer sets it from a host file (nixos) or from a home module, and
  # each class is a separate evaluation.
  declaration =
    { lib, ... }:
    {
      options.kdn.ssh-ca.certificatePatterns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "kdn-*"
          "*.kdn.im"
          "*.nb.net.int.kdn.im"
        ];
        description = ''
          The hosts that may be offered the CA user certificate, as ssh `Host` patterns.

          The directive goes inside a `Host` block, never at the top level: a top-level
          `CertificateFile` is global, so `ssh` would present the fleet's user certificate to every
          destination, including a public host.

          `[ ]` (the default) derives the list from `kdn.ssh-access.identityAgentPatterns` plus
          `kdn-*`, so one definition scopes both the access drop-in and this one. Set it explicitly
          for a host that has no access graph, or to narrow the set.
        '';
      };
    };

  # The client drop-in, and the user certificate it presents.
  dropInPath = ".ssh/config.d/50-kdn-ssh-ca.config";
  userCertPath = "~/.ssh/id_ed25519-cert.pub";

  # The hosts the fleet owns, as ssh `Host` patterns. The client certificate must be offered to
  # these and to nothing else.
  #
  # A top-level `CertificateFile` is global: `ssh_config` would offer the CA user certificate to
  # every destination, including a random public host. So the directive belongs inside a `Host`
  # block that lists the fleet.
  #
  # `[ ]` means "derive": the aspect reads `kdn.ssh-access.identityAgentPatterns` when that option
  # exists, which is the same list the access aspect uses to force `$SSH_AUTH_SOCK` on direct
  # addresses. One definition then scopes both files. `kdn-*` is always included, because those are
  # the fleet aliases the access aspect emits.
  effectivePatterns =
    lib: config:
    let
      declared = config.kdn.ssh-ca.certificatePatterns or [ ];
      fromAccess = config.kdn.ssh-access.identityAgentPatterns or null;
    in
    if declared != [ ] then
      declared
    else if fromAccess != null then
      lib.unique ([ "kdn-*" ] ++ fromAccess)
    else
      # Both sources are absent. Falling back to `[ "kdn-*" ]` alone would silently stop
      # offering the certificate to every direct FQDN and IP connection, which reads as a
      # broken login rather than a configuration error. Fail at evaluation instead.
      throw ''
        kdn.ssh-ca: no `certificatePatterns` and no `kdn.ssh-access.identityAgentPatterns`.

        The client certificate must be scoped to specific hosts, so one of the two must name
        them. Set `kdn.ssh-ca.certificatePatterns` on the host that generates the drop-in
        (the home-manager evaluation, not the host module), or include the `ssh-access`
        aspect in that same evaluation so its pattern list is available.
      '';

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

  # The server directives, as `sshd_config` text. `HostKey` must name the private key behind the
  # host certificate: sshd pairs a `HostCertificate` with a configured identity key, and a managed
  # leaf's key lives at its SOPS runtime path, not beside the store certificate. Measured
  # 2026-10-12 — the two-directive form alone left the issued certificate unused.
  serverDirectives = caPubFile: hostKeyPath: hostCertPath: ''
    TrustedUserCAKeys ${caPubFile}
    HostKey ${hostKeyPath}
    HostCertificate ${hostCertPath}
  '';

  # The SSH CA of one target: the first CA with `ssh = true`. `null` when the consumer declares
  # none, which keeps the whole body a no-op.
  findSshCa = cas: lib: lib.findFirst (ca: ca.ssh) null (lib.attrValues cas);

  # Every leaf with `type = "ssh-host"`: a host may present a classical and a post-quantum
  # identity at once. An empty list when the consumer declares none.
  findHostCerts = certs: lib: lib.filter (cert: cert.type == "ssh-host") (lib.attrValues certs);

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
  #
  # `ca-manager` joins the set so a shell that asks for `ssh-ca` also holds the `kdn-certs` CLI
  # and the CA DAG. A user who signs a user certificate (`kdn-certs ssh login <host>`) and the
  # host that serves it therefore share one aspect. `ca-manager` is devenv-only; on a NixOS or a
  # darwin host it resolves to the no-op, so the host classes above gain no binary.
  kdn.ssh-ca.includes = [
    kdn.ca-dag
    kdn.certificates
    kdn.ca-manager
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
      hostCerts = findHostCerts config.kdn.certificates.certs lib;
    in
    {
      imports = [ declaration ];
      config = lib.mkIf (sshCa != null && hostCerts != [ ]) {
        services.openssh.settings.TrustedUserCAKeys = toString (
          mkSshCaPubKey pkgs (caCertPath config sshCa)
        );
        # The managed key is the ONLY host identity. `hostKeys` replaces nixpkgs' default
        # list (rsa, ed25519, mldsa44), so the installer-generated keys stop being offered and
        # stop being generated. The file is deployed out of band by
        # `kdnctl host ensure ssh-host-keys`, and it is also the host's SOPS identity
        # (`kdn.security.secrets.age` derives it from this path), so sshd and sops must read the
        # same file.
        # Every declared identity, classical and post-quantum. `hostKeys` replaces nixpkgs'
        # default list, so the installer-generated keys stop being offered and generated.
        services.openssh.hostKeys = map (cert: {
          type = cert.keyType;
          path = cert.keyPath;
        }) hostCerts;
        # The certificates are deployed next to the keys, not read from the store: a renewal must
        # not need a rebuild. `kdnctl host ensure ssh-host-certs` writes them and reloads sshd.
        # `settings.HostCertificate` takes a scalar, so the directives go through `extraConfig`,
        # which appends and accepts one line per identity.
        services.openssh.extraConfig = lib.concatMapStrings (cert: ''
          HostCertificate ${cert.deployedCertPath}
        '') hostCerts;
        # The client half below installs the CA fragment per user through home-manager. Root and
        # the nix daemon read none of that, so a den host could not verify a fleet host
        # certificate from a root shell, from `nix copy`, or from a builder connection. Install the
        # same fragment system-wide.
        #
        # `programs.ssh.knownHosts`, not `environment.etc."ssh/ssh_known_hosts"`: the nixpkgs ssh
        # module always defines that path (empty when it has no entries), so a competing `source`
        # silently loses and the file comes out 1 byte long (measured 2026-11-12 on pryll).
        programs.ssh.knownHosts = fleetKnownHosts lib // {
          kdn-ssh-ca = {
            certAuthority = true;
            hostNames = [ "*" ];
            publicKeyFile = mkSshCaPubKey pkgs (caCertPath config sshCa);
          };
        };
        # The declared principals and the inventory are the same list. A manual edit that diverges
        # fails the build instead of producing a certificate for names nobody pins.
        assertions = lib.optional (fleet ? ${config.kdn.hostName}) {
          assertion = lib.all (cert: cert.principals == fleet.${config.kdn.hostName}.names) hostCerts;
          message = ''
            kdn.ssh-ca: the principals of an `ssh-host` leaf do not match
            `data/net/ssh-host-identities.nix`.${config.kdn.hostName}.names.
          '';
        };
        # sshd reads the managed host KEY from its SOPS runtime path, so it must wait for the
        # secrets. A `requires` here is a fault-amplifier though: the target is
        # `BindsTo=sops-install-secrets`, so ONE failed decrypt elsewhere deleted the sshd job and
        # left the host reachable only over a KVM (2026-11-04 on brys). `wants` + `after` keeps the
        # ordering, and a failed decrypt then costs the host certificate, not SSH itself. The HOST
        # KEY is not part of this dependency on a host that syncs it from the repo: see
        # `kdn.ssh-ca.hostKey.autoloadFrom` and `kdnctl host ensure ssh-host-keys`.
        systemd.services.sshd.after = [ "kdn-secrets.target" ];
        systemd.services.sshd.wants = [ "kdn-secrets.target" ];
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
      hostCerts = findHostCerts config.kdn.certificates.certs lib;
    in
    {
      imports = [ declaration ];
      config = lib.mkIf (sshCa != null && hostCerts != [ ]) {
        services.openssh.extraConfig = lib.concatMapStrings (cert: serverDirectives (mkSshCaPubKey pkgs (
          caCertPath config sshCa
        )) cert.keyPath cert.deployedCertPath) hostCerts;
        programs.ssh.knownHosts = fleetKnownHosts lib // {
          kdn-ssh-ca = {
            certAuthority = true;
            hostNames = [ "*" ];
            publicKeyFile = mkSshCaPubKey pkgs (caCertPath config sshCa);
          };
        };
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
      imports = [ declaration ];
      config = lib.mkIf (sshCa != null) {
        # The certificate is scoped to the hosts the fleet owns. A top-level `CertificateFile` is
        # global, so `ssh` would present the CA user certificate to every destination, including a
        # public host; the `Host` block is what keeps it to the fleet.
        #
        # `UserKnownHostsFile` is the opposite case: it must be GLOBAL. Inside the `Host` block it
        # only applied to the fleet patterns, so short names and `kdn-*` aliases never saw the CA
        # fragment — `ssh -G briv` listed only `~/.ssh/known_hosts` (measured 2026-11-12), and
        # `ssh briv` therefore could not verify a host certificate. Additive, so the live file
        # keeps whatever the user appends.
        home.file.${dropInPath}.text = ''
          Host *
              UserKnownHostsFile ~/.ssh/known_hosts ~/${knownHostsPath}

          Host ${lib.concatStringsSep " " (effectivePatterns lib config)}
              CertificateFile ${userCertPath}
        '';
        home.file.${knownHostsPath}.source = mkKnownHosts pkgs (
          mkSshCaPubKey pkgs (caCertPath config sshCa)
        );
      };
    };
}
