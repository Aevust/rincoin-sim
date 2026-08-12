# Rincoin-Sim — Release Build & Signing

Tooling for building, packaging, and GPG-signing a `rincoin-sim` release. This directory automates the manual flow in `doc/build-unix-rincoin-sim.md` §9–§10.

```
contrib/release/
├── Makefile      # build + package + source tarball + signing (this is the entry point)
├── sign.sh       # SHA256SUMS over the archives + detached-armored signature(s)
└── README.md     # this file
```

`rincoin-sim` is a CLI-only Linux functional-test build. Run everything from this directory (`ROOT` is resolved two levels up):

```bash
cd contrib/release
make help          # resolved paths, versions, and the full target list
make release       # depends build + source tarball + detached signature
```

---

## Build methods

Two ways to build the one Linux x86_64 package. `depends` is the **standard**; the native build is a faster alternative for local iteration.

| Command | Method | BDB 4.8 source |
|---------|--------|----------------|
| `make linux` / `make linux-full` | upstream `depends` (**standard**) | built by `depends` |
| `make native-linux` / `make native-linux-full` | native, system libs | `contrib/install_db4.sh` → `db4/` (`BDB_PREFIX`) |

`-full` adds the Qt GUI (`rincoin-qt`); the plain targets are CLI-only. On the `depends` path the GUI toolchain is built by `depends`; on the native path it uses the system Qt5 (`qtbase5-dev qttools5-dev-tools`).

Both methods emit the **same** artifact name — they are two ways to build one package, not two packages. `make release` uses `depends`. Do not expect two files in `OUTDIR` from running both.

> **BDB note.** The `depends` tree builds its own `libdb_cxx-4.8.a`, so `make linux` needs no `install_db4.sh`. If your `depends/packages/` lacks a `bdb` package, the wallet build will fail — use `make native-linux` instead, or pass BDB flags via `EXTRA_CONFIG`.

Every build is logged to `LOGDIR/<target>-<timestamp>.log`; the wrapper exits with the build's real status (`bash PIPESTATUS[0]`), so a failed compile is never masked by `tee`.

---

## Targets

| Target | Does |
|--------|------|
| `linux` / `linux-full` | depends build (CLI / + Qt GUI), logged |
| `native-linux` / `native-linux-full` | native build vs local BDB 4.8, logged |
| `test` | `make check` (C++ unit tests: `test_rincoin` + libsecp256k1) |
| `dist` | source tarball via `git archive` → `rincoin-sim-<VERSION>.tar.gz` |
| `sign` | `SHA256SUMS` over the archives + detached-armored signature |
| `release` | `linux` + `dist` + `sign` |
| `verify` | list artifacts + verify signature + checksums |
| `clean` / `distclean` | remove staging \[ + built `db4/` and `depends/$(HOST)` \] |
| `help` | resolved values + this list (default goal) |

---

## Artifact naming

Matches Rincoin Core: the leading `v` lives **only** on the git tag; distributed files carry the bare version.

| Artifact | Name |
|----------|------|
| Binary package | `rincoin-sim-<VERSION>-x86_64-linux-gnu.tar.gz` |
| Source tarball | `rincoin-sim-<VERSION>.tar.gz` |
| Git tag | `v<VERSION>` |

The binary keeps the GNU host triple specifically so it never collides with the bare-version source tarball — the same reason Core puts the triple on binaries and the bare version on the source archive. `VERSION` is parsed from `configure.ac`; a release candidate (`_CLIENT_VERSION_RC`) becomes a single token `<VERSION>rc<N>` in files and `v<VERSION>-rc<N>` on the tag.

---

## Signing

`rincoin-sim` is a single-maintainer repository, so a release carries **one** signature. Signing is at the **archive** level: `sign.sh` hashes the artifacts into `SHA256SUMS`, then produces a **detached, armored** `SHA256SUMS.asc` with a single key. `sign.sh` re-hashes whatever `rincoin-sim-*.tar.gz` are present, so the manifest always matches the actual artifacts.

```bash
make sign                # default key
make sign KEY=<FPR>      # explicit key
```

Verification (what a downloader runs):

```bash
make verify
# or manually — a detached signature names BOTH files:
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing
```

The default `KEY` is Aevust's `ed25519` key (`0ED99C46B2192E375381EF4AC5BEF8A9FA06C16F`). Override with `KEY=<fpr>`, or edit the default in the `Makefile` / `sign.sh`.

---

## Toggles

`make VAR=value target`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `GUI` | `0` | `1` builds the Qt GUI (same as a `-full` target) |
| `JOBS` | `nproc` | parallel jobs inside the build |
| `VERSION` | from `configure.ac` | file version, no `v` |
| `TAG` | from `configure.ac` | git tag / `git archive` ref |
| `KEY` | Aevust key | GPG signing key |
| `HOST` | `x86_64-linux-gnu` | `depends` host for `make linux` (other Linux hosts work with `STRIP=<triple>-strip`) |
| `STRIP` | `strip` | strip program for staged binaries |
| `BDB_PREFIX` | `<repo>/db4` | local BDB 4.8 prefix (native build) |
| `SCRIPTS_DIR` | `<repo>/scripts` | where the `sim-*.sh` live (override if elsewhere) |
| `LOGDIR` | `~/logs` | per-build log directory |
| `EXTRA_CONFIG` | — | extra `./configure` flags |

> Other Linux hosts (e.g. `aarch64`) can be built with `make linux HOST=aarch64-linux-gnu STRIP=aarch64-linux-gnu-strip`. Windows would need the Core `Makefile`'s `.exe`/`zip` branch and is out of scope here.

---

## Release checklist

1. Land all release commits.
2. `git checkout v<VERSION>` and `git clean -fdx` (keeping `depends`, `db4`, `release`, `release-artifacts`) so the build tree is clean — otherwise `rincoind -version` carries a `-dirty` suffix and the binary is not release-eligible.
3. `make release` — builds via `depends`, snapshots the source, and signs.
4. `make verify` — confirm the `Good signature` line and that the checksums match.
5. Publish the archive(s) + `SHA256SUMS` + `SHA256SUMS.asc` (see `doc/build-unix-rincoin-sim.md` §10-4).
