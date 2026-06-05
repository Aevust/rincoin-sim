# Security Policy

## Official Rincoin Core Team

The following individuals are the current Core Role holders of the Rincoin protocol. **Only individuals listed here are authorized to represent the Rincoin Core Team.**

| Name | Role | Fingerprint |
|------|------|-------------|
| @ysmreg | Founder / Core Technical Lead | (to be added) |
| @Aevust | Core Authority Lead / Core Research Lead / Principal Architect | ED20 B635 4EE4 526D 01F8 3B53 8B6E 3BF4 5C71 4ECA |

Individuals not listed above are **not** members of the Rincoin Core Team, regardless of any claims made elsewhere.

---

## Reporting a Vulnerability

To report security issues, send an email to **info@rincoin.org** (not for general support).

Please do **not** open a public GitHub issue for security-sensitive reports.

Sensitive information may be encrypted using the public keys listed above.

### How to obtain our public key

From the repository (requires a local clone):

```
gpg --import security/Aevust_0x8B6E3BF45C714ECA_public.asc
```

Or from the public keyserver (no clone required):

```
gpg --keyserver hkps://keys.openpgp.org \
    --recv-keys ED20B6354EE4526D01F83B538B6E3BF45C714ECA
```

The key is also viewable at
- [keys.openpgp.org/vks/v1/by-fingerprint/ED20B6354EE4526D01F83B538B6E3BF45C714ECA](https://keys.openpgp.org/vks/v1/by-fingerprint/ED20B6354EE4526D01F83B538B6E3BF45C714ECA)

After import, verify the fingerprint matches the table above:

```
gpg --fingerprint 0x8B6E3BF45C714ECA
```

---

## Verifying Official Communications

Official Rincoin communications are characterized by:

- Signatures from keys listed in this document
- Publication via the official Discord server (owner: @Aevust)
- Publication on **rincoin.org** and **rincoin.com** (operated by @Aevust)
- For protocol-level changes: approval by the Founder (@ysmreg) and Core Strategic Authority as defined in RIP-0001 §Version Authority

For full governance details, canonical sources, and independent DNS verification, see the [RIPs Security Policy](https://github.com/Aevust/rincoin-rips/blob/main/SECURITY.md).
