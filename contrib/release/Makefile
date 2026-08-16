# contrib/release/Makefile — Rincoin-Sim build & sign wrapper
#
# rincoin-sim is a CLI-only Linux functional-test build. Two build methods are
# provided; `depends` is the STANDARD (reproducible, system-independent), and a
# quick native build against a locally built BDB 4.8 is also available:
#
#   make linux            depends x86_64-linux, CLI-only  -> rincoin-sim-<VERSION>-x86_64-linux-gnu.tar.gz  [STANDARD]
#   make linux-full       same, WITH the Qt GUI (depends builds Qt; GUI=1)
#   make native-linux     NATIVE build vs local BDB 4.8 (contrib/install_db4.sh) -> same artifact name
#   make native-linux-full  native, WITH the Qt GUI (system qtbase5-dev)
#   make test             `make check` (test_rincoin + libsecp256k1 C++ unit tests)
#   make dist             source tarball via git archive -> rincoin-sim-<VERSION>.tar.gz
#   make sign             SHA256SUMS + GPG detached-sign (single signer)
#   make release          == make linux && make dist && make sign   (depends flow)
#   make verify           list artifacts + verify signature(s) + checksums
#   make clean            remove staging (keeps db4/ and the depends cache)
#   make distclean        also wipe the built db4/ and depends/$(HOST)
#   make help             this list (default goal)
#
# NAMING (matches Rincoin Core): the leading "v" lives ONLY on the git tag;
# distributed files carry the bare version. The binary keeps the GNU host triple
# (-x86_64-linux-gnu) so it never collides with the bare-version source tarball
# rincoin-sim-<VERSION>.tar.gz — exactly why Core puts the triple on binaries and
# the bare version on the source archive.
#   release :  VERSION = 1.1.0     TAG = v1.1.0      bin rincoin-sim-1.1.0-x86_64-linux-gnu.tar.gz
#   patch   :  VERSION = 1.1.0.1   TAG = v1.1.0.1    bin rincoin-sim-1.1.0.1-x86_64-linux-gnu.tar.gz
#   candidate: VERSION = 1.1.0rc1  TAG = v1.1.0-rc1  bin rincoin-sim-1.1.0rc1-x86_64-linux-gnu.tar.gz
#
# BDB 4.8: the `depends` tree builds its own libdb_cxx-4.8.a (Core's verify
# checklist confirms depends/<host>/lib/libdb_cxx-4.8.a), so `make linux` needs
# no install_db4.sh. Only `make native-linux` uses contrib/install_db4.sh +
# BDB_PREFIX. If your depends tree lacks a bdb package, use native-linux (or pass
# BDB flags via EXTRA_CONFIG).
#
# SIGNING: `make sign` hashes the artifacts into SHA256SUMS and produces a
# detached, armored signature SHA256SUMS.asc with a single key (KEY). rincoin-sim
# is a single-maintainer repository, so exactly one signer is expected.
#
# Every build is captured to a timestamped log under $(LOGDIR) (default ~/logs);
# the wrapper exits with the build's real status (bash PIPESTATUS[0]) so a failed
# compile is never masked by `tee`.
#
# Toggles (make VAR=value target):
#   GUI=1             build the Qt GUI (equivalent to the -full target name)
#   JOBS=8            parallel jobs inside the build (default: nproc)
#   VERSION=1.1.0.1   file version, no "v" (default: parsed from configure.ac)
#   TAG=v1.1.0        git tag / git-archive ref (default from configure.ac)
#   KEY=<fpr>         GPG signing key (default: the maintainer key below)
#   HOST=<triple>     depends host for `make linux` (default x86_64-linux-gnu;
#                     other Linux hosts work with a matching STRIP=<triple>-strip)
#   STRIP=<prog>      strip used on staged binaries (default: strip)
#   BDB_PREFIX=<dir>  locally built BDB 4.8 prefix for native-linux (default <repo>/db4)
#   SCRIPTS_DIR=<dir> where the sim-*.sh live (default <repo>/scripts)
#   LOGDIR=<dir>      where per-build logs are written (default: ~/logs)
#   EXTRA_CONFIG=...  extra ./configure flags

SHELL := /bin/bash

# Keep the shared source tree serial across build/dist/sign (they distclean it).
.NOTPARALLEL:

# Repo root = two levels up from this Makefile (contrib/release/ -> repo root).
ROOT  := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)

JOBS  ?= $(shell nproc 2>/dev/null || echo 4)

# Version from configure.ac (MAJOR.MINOR.REVISION[.BUILD][rcRC]).
# BUILD is the sim-internal patch field: Core keeps it at 0, so it is omitted
# when zero, exactly as AC_INIT does with m4_if(_CLIENT_VERSION_BUILD, [0], []).
# Parsing it here is not cosmetic. BASE feeds TAG, TAG feeds DIST_REF, and
# DIST_REF is the ref `make dist` hands to git archive: with BUILD unparsed, a
# 1.1.0.1 tree would package the v1.1.0 source under a 1.1.0 name while the
# binaries report 1.1.0.1, with no error anywhere.
# Paren-free greps: a literal ')' inside $(shell ...) would close the make
# function early, so we avoid awk field classes / sed capture groups.
V_MAJ := $(shell grep -o '_CLIENT_VERSION_MAJOR, *[0-9][0-9]*' "$(ROOT)/configure.ac" | grep -o '[0-9][0-9]*')
V_MIN := $(shell grep -o '_CLIENT_VERSION_MINOR, *[0-9][0-9]*' "$(ROOT)/configure.ac" | grep -o '[0-9][0-9]*')
V_REV := $(shell grep -o '_CLIENT_VERSION_REVISION, *[0-9][0-9]*' "$(ROOT)/configure.ac" | grep -o '[0-9][0-9]*')
V_BLD := $(shell grep -o '_CLIENT_VERSION_BUILD, *[0-9][0-9]*' "$(ROOT)/configure.ac" | grep -o '[0-9][0-9]*')
V_RC  := $(shell grep -o '_CLIENT_VERSION_RC, *[0-9][0-9]*' "$(ROOT)/configure.ac" | grep -o '[0-9][0-9]*')

# "v" on the git tag only; files carry the bare version (Core convention).
BASE    := $(V_MAJ).$(V_MIN).$(V_REV)$(if $(filter-out 0,$(V_BLD)),.$(V_BLD),)
VERSION ?= $(BASE)$(if $(filter-out 0,$(V_RC)),rc$(V_RC),)
TAG     ?= v$(BASE)$(if $(filter-out 0,$(V_RC)),-rc$(V_RC),)

# depends host (standard build) and the strip used on staged binaries.
HOST        ?= x86_64-linux-gnu
STRIP       ?= strip
# native-linux always targets this host, independent of HOST above.
NATIVE_HOST := x86_64-linux-gnu

# Package names (v-less + GNU triple, matching Core). PKG follows HOST so a
# depends cross-experiment is labelled correctly; NATIVE_PKG is always the native
# host. At the default HOST the two names are identical (one Linux package, two
# ways to build it) — do not expect two files; `make release` uses depends.
PKG        := rincoin-sim-$(VERSION)-$(HOST)
ARTIFACT   := $(PKG).tar.gz
NATIVE_PKG := rincoin-sim-$(VERSION)-$(NATIVE_HOST)

# The sim-*.sh shipped under the package's scripts/ (build-unix §9-3). Path is
# unverified here; override SCRIPTS_DIR=... if they live elsewhere (e.g. contrib/).
SCRIPTS_DIR ?= $(ROOT)/scripts

# Signing key: Aevust ed25519 (personal rincoin-sim repo). Override with KEY=<fpr>.
KEY ?= 0ED99C46B2192E375381EF4AC5BEF8A9FA06C16F

# Staging (assembled package) and final output dir.
RELEASE ?= $(ROOT)/release
OUTDIR  ?= $(ROOT)/release-artifacts
LOGDIR  ?= $(HOME)/logs

# Locally built BDB 4.8 for native-linux (contrib/install_db4.sh writes here).
BDB_PREFIX ?= $(ROOT)/db4

EXTRA_CONFIG ?=

# GUI toggle: CLI-only by default. GUI=1 builds rincoin-qt. depends path toggles
# the depends NO_QT switch; native path relies on system Qt5 (qtbase5-dev).
GUI ?= 0
ifeq ($(GUI),1)
  DEPENDS_QT :=
  GUI_FLAG   := --with-gui=qt5
else
  DEPENDS_QT := NO_QT=1
  GUI_FLAG   := --without-gui
endif

.DEFAULT_GOAL := help

# --- shared staging + packaging ----------------------------------------------
# $(call STAGE_AND_PACKAGE,<pkgname>): copy the CLI (and GUI, if GUI=1) binaries
# from src/ into a versioned staging dir, strip the COPIES (so a running rincoind
# is never touched), add scripts/ + README.md (§9-3), and tar it. One shell
# command (backslash-continued) so the whole block runs under SHELL:=/bin/bash.
define STAGE_AND_PACKAGE
set -e; \
name="$(1)"; dest="$(RELEASE)/$$name"; \
rm -rf "$$dest"; mkdir -p "$$dest/bin"; \
cp "$(ROOT)/src/rincoind" "$(ROOT)/src/rincoin-cli" "$(ROOT)/src/rincoin-tx" "$$dest/bin/"; \
[ -e "$(ROOT)/src/rincoin-wallet" ] && cp "$(ROOT)/src/rincoin-wallet" "$$dest/bin/" || true; \
if [ "$(GUI)" = "1" ] && [ -e "$(ROOT)/src/qt/rincoin-qt" ]; then \
  echo "==> + rincoin-qt (GUI)"; cp "$(ROOT)/src/qt/rincoin-qt" "$$dest/bin/"; \
fi; \
$(STRIP) "$$dest"/bin/* || true; \
if ls "$(SCRIPTS_DIR)"/*.sh >/dev/null 2>&1; then \
  mkdir -p "$$dest/scripts"; cp "$(SCRIPTS_DIR)"/*.sh "$$dest/scripts/"; \
  echo "==> + scripts/ from $(SCRIPTS_DIR)"; \
else \
  echo "==> note: no *.sh in $(SCRIPTS_DIR) — omitting scripts/ (set SCRIPTS_DIR=...)"; \
fi; \
if [ -e "$(ROOT)/README.md" ]; then cp "$(ROOT)/README.md" "$$dest/"; \
else echo "==> note: repo-root README.md not found — skipping"; fi; \
mkdir -p "$(OUTDIR)"; rm -f "$(OUTDIR)/$$name.tar.gz"; \
tar -C "$(RELEASE)" -czf "$(OUTDIR)/$$name.tar.gz" "$$name"; \
echo "==> packaged -> $(OUTDIR)/$$name.tar.gz"
endef

# --- internal build engines --------------------------------------------------
# depends build (standard). depends provides all libs INCLUDING BDB 4.8, so no
# BDB flags and no install_db4.sh here. CONFIG_SITE points ./configure at the
# depends prefix, exactly as in Rincoin Core.
.PHONY: _linux
_linux:
	@echo "==> [depends:$(HOST)] VERSION=$(VERSION)  GUI=$(GUI)  JOBS=$(JOBS)"
	@mkdir -p "$(OUTDIR)"
	@echo "==> [depends] building deps (slow; first run needs network) — includes BDB 4.8"
	$(MAKE) -C "$(ROOT)/depends" HOST=$(HOST) $(DEPENDS_QT) -j$(JOBS)
	@echo "==> [depends] autogen + configure (CONFIG_SITE=depends/$(HOST))"
	cd "$(ROOT)" && ./autogen.sh
	cd "$(ROOT)" && CONFIG_SITE="$(ROOT)/depends/$(HOST)/share/config.site" \
	    ./configure --prefix=/ $(GUI_FLAG) --disable-bench --with-pic $(EXTRA_CONFIG)
	@echo "==> [depends] make -j$(JOBS)"
	$(MAKE) -C "$(ROOT)" -j$(JOBS)
	@echo "==> [depends] assemble + package: $(PKG)"
	@$(call STAGE_AND_PACKAGE,$(PKG))
	@echo "==> [depends] distclean source tree (depends/ cache kept)"
	-cd "$(ROOT)" && $(MAKE) distclean >/dev/null 2>&1
	@echo "==> [depends] DONE -> $(OUTDIR)/$(ARTIFACT)"

# native build. Builds a local BDB 4.8 via contrib/install_db4.sh on first run,
# then configures against system libs + that BDB, exactly as in build-unix §2-4.
.PHONY: _native-linux
_native-linux:
	@echo "==> [native:$(NATIVE_HOST)] VERSION=$(VERSION)  GUI=$(GUI)  JOBS=$(JOBS)"
	@mkdir -p "$(OUTDIR)"
	@if [ ! -e "$(BDB_PREFIX)/lib/libdb_cxx-4.8.a" ]; then \
	    echo "==> [native] building BDB 4.8 into $(BDB_PREFIX) (first run only)"; \
	    "$(ROOT)/contrib/install_db4.sh" "$(ROOT)"; \
	 else echo "==> [native] BDB 4.8 present: $(BDB_PREFIX)"; fi
	@echo "==> [native] autogen + configure ($(GUI_FLAG); system libs + local BDB)"
	cd "$(ROOT)" && ./autogen.sh
	cd "$(ROOT)" && ./configure --without-miniupnpc $(GUI_FLAG) --disable-bench --with-pic \
	    BDB_LIBS="-L$(BDB_PREFIX)/lib -ldb_cxx-4.8" \
	    BDB_CFLAGS="-I$(BDB_PREFIX)/include" \
	    $(EXTRA_CONFIG)
	@echo "==> [native] make -j$(JOBS)"
	$(MAKE) -C "$(ROOT)" -j$(JOBS)
	@echo "==> [native] assemble + package: $(NATIVE_PKG)"
	@$(call STAGE_AND_PACKAGE,$(NATIVE_PKG))
	@echo "==> [native] distclean source tree (db4/ kept)"
	-cd "$(ROOT)" && $(MAKE) distclean >/dev/null 2>&1
	@echo "==> [native] DONE -> $(OUTDIR)/$(NATIVE_PKG).tar.gz"

# --- logged public build targets ---------------------------------------------
CLI_TARGETS  := linux native-linux
FULL_TARGETS := linux-full native-linux-full
.PHONY: $(CLI_TARGETS) $(FULL_TARGETS)

$(CLI_TARGETS):
	@mkdir -p "$(LOGDIR)"
	@log="$(LOGDIR)/$@-$$(date +%F-%H%M%S).log"; \
	 echo "==> [$@] logging to $$log"; \
	 set -o pipefail; \
	 $(MAKE) _$@ GUI=$(GUI) 2>&1 | tee "$$log"; \
	 rc=$${PIPESTATUS[0]}; \
	 echo "==> [$@] build exit: $$rc"; \
	 echo "    log: $$log"; \
	 exit $$rc

$(FULL_TARGETS):
	@mkdir -p "$(LOGDIR)"
	@log="$(LOGDIR)/$@-$$(date +%F-%H%M%S).log"; \
	 echo "==> [$@] logging to $$log"; \
	 set -o pipefail; \
	 $(MAKE) _$(patsubst %-full,%,$@) GUI=1 2>&1 | tee "$$log"; \
	 rc=$${PIPESTATUS[0]}; \
	 echo "==> [$@] build exit: $$rc"; \
	 echo "    log: $$log"; \
	 exit $$rc

# --- unit tests (optional; not part of `release`) ----------------------------
.PHONY: test
test:
	@echo "==> [test] make check (C++ unit tests)"
	$(MAKE) -C "$(ROOT)" check
	@echo
	@echo "==> functional RIN3 tests run separately, in a venv with blake3 + argon2-cffi:"
	@echo "    source ~/rincoin-venv/bin/activate"
	@echo "    test/functional/test_runner.py feature_rin3_enforcement.py"

# --- source tarball via git archive ------------------------------------------
# Snapshot of the signed tag (modern Bitcoin Core style: no generated ./configure,
# so the builder runs ./autogen.sh first). Bare-version name so sign.sh's glob
# (rincoin-sim-*.tar.gz) picks it up. gzip -n drops the stream timestamp; git
# archive fixes entry mtimes -> same tag, same bytes.
# Dry-run before tagging with:  make dist DIST_REF=HEAD
DIST_REF ?= $(TAG)

.PHONY: dist
dist:
	@mkdir -p "$(OUTDIR)"
	@git -C "$(ROOT)" rev-parse -q --verify "$(DIST_REF)^{commit}" >/dev/null || { \
	    echo "error: git ref '$(DIST_REF)' not found in $(ROOT)" >&2; \
	    echo "       tag the release first, or dry-run with: make dist DIST_REF=HEAD" >&2; \
	    exit 1; \
	 }
	@echo "==> [dist] git archive $(DIST_REF) -> rincoin-sim-$(VERSION).tar.gz"
	@git -C "$(ROOT)" archive --format=tar --prefix="rincoin-sim-$(VERSION)/" "$(DIST_REF)" \
	    | gzip -9n > "$(OUTDIR)/rincoin-sim-$(VERSION).tar.gz"
	@echo "    -> $(OUTDIR)/rincoin-sim-$(VERSION).tar.gz ($$(du -h "$(OUTDIR)/rincoin-sim-$(VERSION).tar.gz" | cut -f1))"

# --- signing -----------------------------------------------------------------
# (re)hash the artifacts -> SHA256SUMS, then produce a detached, armored
# signature SHA256SUMS.asc with KEY. Single signer (personal repository).
.PHONY: sign
sign:
	@bash "$(ROOT)/contrib/release/sign.sh" "$(OUTDIR)" $(KEY)

# --- full release flow (depends) ---------------------------------------------
# Build the standard depends target, snapshot the source, sign. For a real
# release, run from a CLEAN, TAGGED tree (git checkout $(TAG) first) so
# `rincoind -version` carries no -dirty suffix.
.PHONY: release
release:
	@$(MAKE) linux
	@$(MAKE) dist
	@$(MAKE) sign

.PHONY: verify
verify:
	@echo "Artifacts in $(OUTDIR):"
	@ls -l "$(OUTDIR)"/rincoin-sim-* 2>/dev/null || echo "  (none — run 'make linux' first)"
	@echo
	@echo "Signature:"
	@if [ -f "$(OUTDIR)/SHA256SUMS.asc" ]; then \
	    ( cd "$(OUTDIR)" && gpg --verify SHA256SUMS.asc SHA256SUMS ); \
	 else echo "  (no SHA256SUMS.asc yet — run 'make sign')"; fi
	@echo
	@echo "Checksums:"
	@if [ -f "$(OUTDIR)/SHA256SUMS" ]; then \
	    ( cd "$(OUTDIR)" && sha256sum -c SHA256SUMS --ignore-missing ); \
	 else echo "  (no SHA256SUMS yet — run 'make sign')"; fi
	@echo
	@echo "rincoin-sim is a single-host x86_64-linux build; the Core §10-6"
	@echo "cross-build checklist (wine/qemu-user) does NOT apply. Confirm here:"
	@echo "  - ./bin/rincoind -version reports the $(TAG) version (no -dirty)"
	@echo "  - depends build: depends/$(HOST)/lib/libdb_cxx-4.8.a exists"
	@echo "  - make test passes (test_rincoin + libsecp256k1)"
	@echo "  - functional: test/functional/test_runner.py feature_rin3_enforcement.py"

.PHONY: clean
clean:
	rm -rf "$(RELEASE)"
	-cd "$(ROOT)" && $(MAKE) distclean >/dev/null 2>&1

.PHONY: distclean
distclean: clean
	rm -rf "$(BDB_PREFIX)" "$(ROOT)/depends/$(HOST)"

.PHONY: help
help:
	@echo "Rincoin-Sim — Linux build & sign (depends standard; native optional)"
	@echo
	@echo "  make linux | linux-full         depends x86_64-linux build (CLI | + Qt GUI), logged  [STANDARD]"
	@echo "  make native-linux | ...-full    native build vs local BDB 4.8 (CLI | + Qt GUI), logged"
	@echo "  make test                       make check (C++ unit tests)"
	@echo "  make dist                       source tarball via git archive (rincoin-sim-<VERSION>.tar.gz)"
	@echo "  make sign                       SHA256SUMS + GPG detached-sign (single signer)"
	@echo "  make release                    linux + dist + sign  (depends flow)"
	@echo "  make verify                     list artifacts + verify signature(s) + checksums"
	@echo "  make clean | distclean          remove staging [ + built db4/ and depends/\$$(HOST) ]"
	@echo
	@echo "  each build tees to LOGDIR/<target>-<timestamp>.log"
	@echo "  toggles: GUI=1  JOBS=N  VERSION=X.Y.Z  KEY=<fpr>  HOST=<triple>  BDB_PREFIX=<dir>  SCRIPTS_DIR=<dir>"
	@echo
	@echo "  ROOT       = $(ROOT)"
	@echo "  VERSION    = $(VERSION)   (files, no v)      TAG = $(TAG)   (git tag)"
	@echo "  depends bin= $(ARTIFACT)"
	@echo "  native bin = $(NATIVE_PKG).tar.gz"
	@echo "  source     = rincoin-sim-$(VERSION).tar.gz"
	@echo "  KEY        = $(KEY)"
	@echo "  HOST       = $(HOST)      BDB_PREFIX = $(BDB_PREFIX)"
	@echo "  SCRIPTS_DIR= $(SCRIPTS_DIR)"
	@echo "  LOGDIR     = $(LOGDIR)    OUTDIR = $(OUTDIR)"
