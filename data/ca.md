# KDN Certificate Authority

This directory holds the certificate authority (CA) material used to sign leaf
certificates for KDN services, notably the LLM endpoint on `brys`.

## Files

| File | Contents | Automation? |
|---|---|---|
| `ca.pub` | PEM public CA certificate (self-signed, EC P-256, 100 years) | trusted via the `kdn.ca` slot |
| `ca.key.sops` | SOPS-encrypted CA **private** key (raw/binary format) | **not** read by automation yet; path is exposed via `kdn.ca.keySopsFile` for reference only |

The CA private key must never be loaded by a running service. It is kept
encrypted on disk and only decrypted manually when (re)signing a leaf cert.

## Decoding the CA key

The CA key is a raw SOPS binary file. Decrypt it on demand:

```bash
sops decrypt --output-type binary data/ca.key.sops > /tmp/ca.key
```

The decrypted file is an EC private key (PEM):

```bash
openssl pkey -in /tmp/ca.key -noout -check
```

## Generating a leaf certificate

Leaf certs are stored per host under `hosts/<name>/certs/`. Example SAN set for
the brys LLM endpoint (etra LAN, drek LAN, netbird priv):

```bash
subj=/CN=brys.lan.etra.net.int.kdn.im
sans="DNS:brys.lan.etra.net.int.kdn.im,DNS:brys.lan.drek.net.int.kdn.im,DNS:brys.priv.nb.net.int.kdn.im"

# leaf private key
openssl ecparam -name prime256v1 -genkey -noout -out llm.key

# CSR
openssl req -new -key llm.key -out llm.csr -sha256 \
  -subj "$subj" -addext "subjectAltName=$sans"

# sign with the CA (decode the CA key first, see above)
openssl x509 -req -in llm.csr -CA data/ca.pub -CAkey /tmp/ca.key \
  -CAcreateserial -out llm.pub -days 3650 -sha256 \
  -copy_extensions copy

# verify
openssl verify -CAfile data/ca.pub llm.pub
```

## Storing a leaf certificate

- The **public** leaf cert is committed in raw form, e.g.
  `hosts/<name>/certs/llm.pub`.
- The **private** leaf key is SOPS-encrypted (raw/binary) next to it, e.g.
  `hosts/<name>/certs/llm.key.sops`:

```bash
sops encrypt --age "$SOPS_AGE_RECIPIENTS" --output-type binary \
  --output hosts/<name>/certs/llm.key.sops llm.key
```

Use the same age recipients as the other KDN sops files (see any `*.sops.yaml`
`age:` block for the current recipients, or `SOPS_AGE_RECIPIENTS`).

## Trust

Add `data/ca.pub` to the system CA authorities on the hosts that consume
services signed by this CA via the `kdn.ca` slot (`security.pki.certificateFiles`).
