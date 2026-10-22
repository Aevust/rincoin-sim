#!/usr/bin/env bash
# Rincoin-Sim: RIN3 boundary behaviour and raw-transaction RPC versions
# Usage: ./scripts/sim-rin3-boundary.sh [BUILD_DIR]
#        EXPECT_FUND_MARKER=1 ./scripts/sim-rin3-boundary.sh [BUILD_DIR]
#
# Purpose:
#   Two nodes on regtest (fork height 840), loopback only, datadirs under /tmp.
#   Node A mines; node B holds a pre-fork legacy transaction across activation.
#   Measures the behaviour RIP-0009 specifies at the boundary, and records what
#   the raw-transaction RPCs produce there.
#
#   W  Wallet version switch (RIP-0009 section 5): a transaction built at tip
#      838 carries nVersion 2; one built at tip 839 carries 0x52494e33 and is
#      mined into block 840.
#   S  Block 840 pays the Customized Halving subsidy (4.00 RIN at 1/1000 scale).
#   R  Mempool cleanup (CTxMemPool::removeForRIN3Fork): when B connects
#      block 839 it removes T, the wallet can abandon T at once, and a
#      re-creation from T's inputs carries the marker, reaches A and is mined.
#   Z  Layer 3, mixed mode only (BUILD_B): an older B, which keeps a
#      pre-fork legacy transaction in its mempool after activation, still
#      produces blocks, and they omit it.
#   P  Layer 2 classification, mixed mode only: that transaction, relayed
#      to A after activation, is rejected as bad-tx-rinhash-version, twice
#      across a new block and a reconnection, and the relaying peer is
#      neither discouraged nor disconnected; A does not take it back.
#   C  Several blocks in a row, mixed mode only: after P (and F), A mines
#      three more blocks; the older B follows each one, both stay connected,
#      neither logs Misbehaving, and no block contains T.
#   F  Raw-transaction RPCs after activation. Without EXPECT_FUND_MARKER the
#      versions that createrawtransaction + fundrawtransaction and
#      walletcreatefundedpsbt produce are recorded as notes (on v1.1.0-rc1
#      they are 2, and the transaction is rejected). With EXPECT_FUND_MARKER=1
#      they are checks: the funded transaction must carry the marker and send.
#      In both modes, the marker set before funding must survive funding.
#
# Binaries: BUILD_DIR/src or BUILD_DIR/bin when BUILD_DIR is given; otherwise
#   resolved relative to this script (../bin, then ../src), as the other
#   scripts do. The tree must report version 1.1.0.
#   BUILD_B=<dir> (mixed mode) runs node B from that build instead (bin/ or
#   src/), e.g. a release without the cleanup; B is still driven with this
#   build's rincoin-cli. Single mode checks R; mixed mode checks Z, P and C.
#
# Environment: SIM_TMP is the parent of the two datadirs (default /tmp).
#
# Exit 0 only if every check passes. Datadirs are kept for inspection.
#
# Companion scripts:
#   scripts/sim-ch-rin3.sh   -- CH x RIN3 regression suite (~5 min)
#   scripts/sim-ch-attack.sh -- CH subsidy reorg showcase (~15-20 min)

set -euo pipefail

# ---------- Binary detection ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD=${1:-$PKG_ROOT}
if [ -f "$BUILD/bin/rincoind" ]; then
    NODE="$BUILD/bin/rincoind"; CLI="$BUILD/bin/rincoin-cli"
elif [ -f "$BUILD/src/rincoind" ]; then
    NODE="$BUILD/src/rincoind"; CLI="$BUILD/src/rincoin-cli"
else
    echo "Error: rincoind not found under $BUILD/bin/ or $BUILD/src/."
    exit 1
fi
EXPECT_FUND_MARKER=${EXPECT_FUND_MARKER:-0}
SIM_TMP=${SIM_TMP:-/tmp}
BUILD_B=${BUILD_B:-}
NODE_B="$NODE"
if [ -n "$BUILD_B" ]; then
    if [ -f "$BUILD_B/bin/rincoind" ]; then
        NODE_B="$BUILD_B/bin/rincoind"
    elif [ -f "$BUILD_B/src/rincoind" ]; then
        NODE_B="$BUILD_B/src/rincoind"
    else
        echo "Error: rincoind not found under $BUILD_B/bin/ or $BUILD_B/src/."
        exit 1
    fi
fi
P2P=29700
RPCA=29701
RPCB=29711
FORK=840
MARKER_DEC=1380535859
MARKER_HEX_LE=334e4952
FEE=0.001

PASS=0
FAIL=0
INCONCLUSIVE=0
ok()   { echo "  [PASS] $*"; PASS=$((PASS + 1)); }
ng()   { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
inc()  { echo "  [INCONCLUSIVE] $*"; INCONCLUSIVE=$((INCONCLUSIVE + 1)); }
note() { echo "  [NOTE] $*"; }
die()  { echo "ABORT: $*"; exit 2; }

DA=$(mktemp -d "$SIM_TMP/rin3-a.XXXXXX")
DB=$(mktemp -d "$SIM_TMP/rin3-b.XXXXXX")
LOGA="$DA/regtest/debug.log"
LOGB="$DB/regtest/debug.log"

a() { "$CLI" -regtest -datadir="$DA" -rpcport="$RPCA" "$@"; }
b() { "$CLI" -regtest -datadir="$DB" -rpcport="$RPCB" "$@"; }

# j EXPR -- evaluate a Python expression over the JSON on stdin (as d)
j() {
    python3 -c 'import sys, json, decimal
d = json.load(sys.stdin, parse_float=decimal.Decimal)
print(eval(sys.argv[1]))' "$1"
}
version_of() {   # $1 = a|b, $2 = txid  -> nVersion as seen by that node
    "$1" getrawtransaction "$2" true | j 'd["version"]'
}
running() { pgrep -f -- "-datadir=$1" >/dev/null 2>&1; }

wait_rpc() {   # $1 = a|b
    local i
    for i in $(seq 1 90); do
        "$1" getblockcount >/dev/null 2>&1 && return 0
        sleep 1
    done
    die "RPC did not come up ($1)"
}
wait_height() {   # $1 = a|b, $2 = height, $3 = seconds
    local i
    for i in $(seq 1 "$3"); do
        [ "$("$1" getblockcount)" -ge "$2" ] && return 0
        sleep 1
    done
    return 1
}
wait_conn() {   # $1 = a|b, $2 = expected count, $3 = seconds
    local i
    for i in $(seq 1 "$3"); do
        [ "$("$1" getconnectioncount)" = "$2" ] && return 0
        sleep 1
    done
    return 1
}
wait_log() {   # $1 = pattern, $2 = minimum count, $3 = seconds
    local i n
    for i in $(seq 1 "$3"); do
        n=$(grep -c -E -- "$1" "$LOGA" 2>/dev/null || true)
        [ "${n:-0}" -ge "$2" ] && return 0
        sleep 1
    done
    return 1
}
mine() {   # $1 = a|b, $2 = count, $3 = address; prints the last block hash
    local node=$1 n=$2 addr=$3 batch last
    while [ "$n" -gt 0 ]; do
        batch=$(( n > 500 ? 500 : n ))
        last=$("$node" generatetoaddress "$batch" "$addr" | j 'd[-1]')
        n=$((n - batch))
    done
    echo "$last"
}

stop_node() {   # $1 = a|b, $2 = datadir
    "$1" stop >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 60); do
        running "$2" || return 0
        sleep 1
    done
    echo "warning: node with datadir $2 still running after 60 s"
}
cleanup() {
    stop_node b "$DB"
    stop_node a "$DA"
    echo "# datadirs kept: $DA $DB"
}
trap cleanup EXIT

# ------------------------------------------------------------------ identity
echo "# commit  $(git -C "$BUILD" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "# script  scripts/$(basename "$0")  sha256 $(sha256sum "$0" | cut -d' ' -f1)"
echo "# started $(date -Iseconds)"
echo "# host    $(uname -srm)"
echo "# mode    EXPECT_FUND_MARKER=$EXPECT_FUND_MARKER  $( [ -n "$BUILD_B" ] && echo "mixed (BUILD_B=$BUILD_B)" || echo single )"
echo "# datadirs $DA  $DB"
for f in "$NODE" "$CLI" $( [ -n "$BUILD_B" ] && echo "$NODE_B" ); do
    [ -x "$f" ] || die "missing or not executable: $f"
    echo "# sha256   $(sha256sum "$f")"
    echo "# buildid  $(basename "$f")  $(file -b "$f" | grep -o 'BuildID\[sha1\]=[0-9a-f]*' || echo 'n/a')"
done
if [ -d "$BUILD/.git" ]; then
    echo "# describe $(git -C "$BUILD" describe --tags --always --dirty 2>/dev/null || true)"
fi
VERLINE=$("$NODE" -version | sed -n 1p)
echo "# version  $VERLINE"
case "$VERLINE" in
    *1.1.0*) ;;
    *) die "binary does not report 1.1.0" ;;
esac
if [ -n "$BUILD_B" ]; then
    VERLINE_B=$("$NODE_B" -version | sed -n 1p)
    echo "# version B $VERLINE_B"
    case "$VERLINE_B" in
        *1.1.0*) ;;
        *) die "BUILD_B binary does not report 1.1.0" ;;
    esac
fi
BUSY=$(ss -ltn 2>/dev/null | grep -cE ":(${P2P}|${RPCA}|${RPCB})\b" || true)
[ "$BUSY" = 0 ] || die "port $P2P, $RPCA or $RPCB already in use"

# ------------------------------------------------------------------ setup
echo
echo "== setup: A mines and listens; B connects to A =="
# -debug=mempool: R reads the cleanup's per-transaction line, which a release
# may log under that category only. -debug=net on B as well, so that C's
# Misbehaving check reads a log that would show it.
"$NODE" -regtest -datadir="$DA" -rpcport="$RPCA" -connect=0 -listen=1 -bind=127.0.0.1 \
    -port="$P2P" -discover=0 -debug=mempoolrej -debug=mempool -debug=net -fallbackfee="$FEE" -daemon >/dev/null
wait_rpc a
"$NODE_B" -regtest -datadir="$DB" -rpcport="$RPCB" -listen=0 -connect="127.0.0.1:$P2P" \
    -debug=mempoolrej -debug=mempool -debug=net -fallbackfee="$FEE" -daemon >/dev/null
wait_rpc b
wait_conn b 1 60 || die "B did not connect to A"

a createwallet wa >/dev/null
b createwallet wb >/dev/null
AA=$(a getnewaddress)
AB=$(b getnewaddress)

NIA=$(a getnetworkinfo)
echo "  A: $(j 'd["subversion"]' <<<"$NIA")  proto $(j 'd["protocolversion"]' <<<"$NIA")  services $(j '",".join(d["localservicesnames"])' <<<"$NIA")"
if [ "$(j '"RIN3" in d["localservicesnames"]' <<<"$NIA")" = True ]; then
    ok "A advertises NODE_RIN3"
else
    ng "A does not advertise NODE_RIN3"
fi
PIA=$(a getpeerinfo)
if [ "$(j 'any(p["inbound"] and "RIN3" in p["servicesnames"] for p in d)' <<<"$PIA")" = True ]; then
    ok "A sees B inbound with NODE_RIN3"
else
    ng "A's peer list: $(j 'json.dumps([(p["inbound"], p["servicesnames"]) for p in d])' <<<"$PIA")"
fi

mine a 10 "$AB" >/dev/null                 # B's coins, mature from height 110
mine a $((FORK - 2 - 10)) "$AA" >/dev/null # to 838
[ "$(a getblockcount)" = $((FORK - 2)) ] || die "A is at $(a getblockcount), expected $((FORK - 2))"
wait_height b $((FORK - 2)) 180 || die "B did not sync to $((FORK - 2))"
if [ "$(a getbestblockhash)" = "$(b getbestblockhash)" ]; then
    ok "A and B agree at height $((FORK - 2))"
else
    ng "A and B disagree at height $((FORK - 2))"
fi

# ------------------------------------------------------------------ W (legacy side)
echo
echo "== W: B builds a transaction at tip $((FORK - 2)) while disconnected =="
b setnetworkactive false >/dev/null
wait_conn b 0 30 || die "B still connected after setnetworkactive false"
b syncwithvalidationinterfacequeue >/dev/null
T=$(b sendtoaddress "$AB" 1)
TV=$(version_of b "$T")
THEX=$(b getrawtransaction "$T")
echo "  T $T  nVersion $TV"
if [ "$TV" = 2 ]; then
    ok "W: at tip $((FORK - 2)) the wallet emits nVersion 2"
else
    ng "W: at tip $((FORK - 2)) the wallet emitted nVersion $TV"
fi
if b getmempoolentry "$T" >/dev/null 2>&1; then
    ok "T is in B's mempool"
else
    ng "T is not in B's mempool"
fi

# ------------------------------------------------------------------ W (marker side) + S
echo
echo "== W/S: A builds a transaction at tip $((FORK - 1)) and mines the fork block =="
mine a 1 "$AA" >/dev/null
a syncwithvalidationinterfacequeue >/dev/null
U=$(a sendtoaddress "$AA" 1)
UV=$(version_of a "$U")
echo "  U $U  nVersion $UV"
if [ "$UV" = "$MARKER_DEC" ]; then
    ok "W: at tip $((FORK - 1)) the wallet emits nVersion $MARKER_DEC"
else
    ng "W: at tip $((FORK - 1)) the wallet emitted nVersion $UV"
fi
BH_FORK=$(mine a 1 "$AA")
[ "$(a getblockcount)" = "$FORK" ] || die "A is at $(a getblockcount), expected $FORK"
if [ "$(a getblock "$BH_FORK" | j "\"$U\" in d[\"tx\"]")" = True ]; then
    ok "W: block $FORK contains U"
else
    ng "W: block $FORK does not contain U"
fi
S839=$(a getblockstats $((FORK - 1)) | j 'd["subsidy"]')
S840=$(a getblockstats "$FORK" | j 'd["subsidy"]')
echo "  subsidy $((FORK - 1)) = $S839  $FORK = $S840"
if [ "$S839" = 625000000 ] && [ "$S840" = 400000000 ]; then
    ok "S: subsidy 6.25 RIN at $((FORK - 1)), 4.00 RIN at $FORK"
else
    ng "S: unexpected subsidies"
fi

# ------------------------------------------------------------------ Z
echo
echo "== B reconnects and syncs across activation =="
b setnetworkactive true >/dev/null
wait_conn b 1 60 || die "B did not reconnect"
wait_height b "$FORK" 120 || die "B did not sync to $FORK"
if [ "$(b getbestblockhash)" = "$BH_FORK" ]; then
    ok "B follows A to block $FORK"
else
    ng "B's tip is $(b getbestblockhash) at $(b getblockcount)"
fi
RESIDUE=0
if b getmempoolentry "$T" >/dev/null 2>&1; then
    RESIDUE=1
    note "pre-fork residue: T stays in B's mempool after block $FORK connects"
else
    note "T is no longer in B's mempool at tip $FORK"
fi
if [ -z "$BUILD_B" ]; then
    # -------------------------------------------------------------- R (single mode)
    echo
    echo "== R: B removed T when block $((FORK - 1)) connected; abandon and re-creation =="
    if [ "$RESIDUE" = 0 ] && grep -q -- "RIN3 fork: removing $T " "$LOGB"; then
        ok "R: B removed T at block $((FORK - 1)): $(grep -m1 -- "RIN3 fork: removing $T " "$LOGB" | cut -d' ' -f2-)"
    else
        ng "R: T was not removed by the cleanup (still in B's mempool: $RESIDUE)"
    fi
    if b abandontransaction "$T" >/dev/null 2>&1; then
        ok "R: B's wallet abandons T at once, without a restart"
    else
        ng "R: abandontransaction T failed: $(b abandontransaction "$T" 2>&1 | tr '\n' ' ')"
    fi
    TINPUTS=$(b decoderawtransaction "$(b gettransaction "$T" | j 'd["hex"]')" \
              | j 'json.dumps([{"txid": i["txid"], "vout": i["vout"]} for i in d["vin"]])')
    RFUND=$(b fundrawtransaction "$(b createrawtransaction "$TINPUTS" "[{\"$AB\":1}]")" | j 'd["hex"]')
    RV=$(b decoderawtransaction "$RFUND" | j 'd["version"]')
    if ROUT=$(b sendrawtransaction "$(b signrawtransactionwithwallet "$RFUND" | j 'd["hex"]')" 2>&1); then
        RT=$ROUT
        echo "  re-creation $RT  nVersion $RV"
        for i in $(seq 1 60); do
            a getmempoolentry "$RT" >/dev/null 2>&1 && break
            sleep 1
        done
        if [ "$RV" = "$MARKER_DEC" ] && a getmempoolentry "$RT" >/dev/null 2>&1; then
            ok "R: the re-creation from T's inputs carries nVersion $MARKER_DEC and reaches A's mempool"
        else
            ng "R: re-creation nVersion $RV; in A's mempool: $(a getmempoolentry "$RT" >/dev/null 2>&1 && echo yes || echo no)"
        fi
    else
        RT=none
        ng "R: B refused the re-creation (nVersion $RV): $(echo "$ROUT" | tr '\n' ' ')"
    fi
    BHR=$(mine a 1 "$AA")
    if [ "$RT" != none ] && [ "$(a getblock "$BHR" | j "\"$RT\" in d[\"tx\"]")" = True ]; then
        ok "R: block $((FORK + 1)) contains the re-creation"
    else
        ng "R: block $((FORK + 1)) does not contain the re-creation"
    fi
    wait_height b $((FORK + 1)) 60 || die "B did not sync to $((FORK + 1))"
elif [ "$RESIDUE" = 1 ]; then
    echo
    echo "== Z: B (BUILD_B) mines with T in its mempool =="
    BH841=$(mine b 1 "$AB")
    if [ "$(b getblockcount)" = $((FORK + 1)) ]; then
        ok "Z: B produced block $((FORK + 1)) with T in its mempool"
    else
        ng "Z: B is at $(b getblockcount) after generatetoaddress"
    fi
    if [ "$(b getblock "$BH841" | j "\"$T\" in d[\"tx\"]")" = False ]; then
        ok "Z: block $((FORK + 1)) omits T"
    else
        ng "Z: block $((FORK + 1)) contains T"
    fi
    if wait_height a $((FORK + 1)) 60 && [ "$(a getbestblockhash)" = "$BH841" ]; then
        ok "Z: A accepted B's block $((FORK + 1))"
    else
        ng "Z: A is at $(a getblockcount), tip $(a getbestblockhash)"
    fi
else
    ng "Z: B (BUILD_B) did not keep T after block $FORK"
fi

# ------------------------------------------------------------------ P (mixed mode)
if [ -n "$BUILD_B" ] && [ "$RESIDUE" = 1 ]; then
    echo
    echo "== P: B relays T to A after activation, twice across a new block =="
    REJ="$T from peer=[0-9]+ was not accepted: bad-tx-rinhash-version"
    R1=$(b sendrawtransaction "$THEX")
    [ "$R1" = "$T" ] && ok "B re-announced T (sendrawtransaction on a mempool transaction relays it)" \
                     || ng "sendrawtransaction returned $R1"
    if wait_log "$REJ" 1 90; then
        ok "P: A rejected T: $(grep -m1 -E -- "$REJ" "$LOGA" | cut -d' ' -f2-)"
    else
        inc "P: no rejection of T logged on A within 90 s"
        grep -- "$T" "$LOGA" 2>/dev/null | tail -3 | sed 's/^/    /' || true
    fi
    mine a 1 "$AA" >/dev/null       # new tip resets A's recentRejects
    wait_height b $((FORK + 2)) 60 || die "B did not sync to $((FORK + 2))"
    # A peer announces a given transaction to a given peer once: filterInventoryKnown
    # is per connection, so a repeat needs a fresh connection, which is also how the
    # repeat arises in practice (another peer, or one that reconnected).
    b setnetworkactive false >/dev/null
    wait_conn b 0 30 || die "B did not drop its connection"
    b setnetworkactive true >/dev/null
    wait_conn b 1 60 || die "B did not reconnect"
    b sendrawtransaction "$THEX" >/dev/null
    if wait_log "$REJ" 2 90; then
        ok "P: A rejected T again after a new block and a reconnect ($(grep -c -E -- "$REJ" "$LOGA") rejections logged)"
    else
        inc "P: second rejection not logged within 90 s"
        grep -- "$T" "$LOGA" 2>/dev/null | tail -3 | sed 's/^/    /' || true
    fi
    MB=$(grep -c 'Misbehaving' "$LOGA" || true)
    if [ "${MB:-0}" = 0 ]; then
        ok "P: no Misbehaving entry on A"
    else
        ng "P: Misbehaving logged on A:"; grep 'Misbehaving' "$LOGA" | tail -3 | sed 's/^/    /'
    fi
    if [ "$(b getconnectioncount)" = 1 ] && [ "$(a getconnectioncount)" = 1 ]; then
        ok "P: A and B are still connected"
    else
        ng "P: connections A=$(a getconnectioncount) B=$(b getconnectioncount)"
    fi
    if a getmempoolentry "$T" >/dev/null 2>&1; then
        ng "P: T is in A's mempool"
    else
        ok "P: T is absent from A's mempool"
    fi
fi

# ------------------------------------------------------------------ F
echo
echo "== F: raw-transaction RPCs on A at tip $(a getblockcount) (EXPECT_FUND_MARKER=$EXPECT_FUND_MARKER) =="
RAW=$(a createrawtransaction '[]' "[{\"$AA\":1}]")
FUND=$(a fundrawtransaction "$RAW" | j 'd["hex"]')
FV=$(a decoderawtransaction "$FUND" | j 'd["version"]')
SIGNED=$(a signrawtransactionwithwallet "$FUND" | j 'd["hex"]')
if SENT=$(a sendrawtransaction "$SIGNED" 2>&1); then SENT_OK=1; else SENT_OK=0; fi
PSBT=$(a walletcreatefundedpsbt '[]' "[{\"$AA\":1}]" | j 'd["psbt"]')
PV=$(a decodepsbt "$PSBT" | j 'd["tx"]["version"]')
if [ "$EXPECT_FUND_MARKER" = 1 ]; then
    if [ "$FV" = "$MARKER_DEC" ]; then
        ok "F: fundrawtransaction emits nVersion $MARKER_DEC after activation"
    else
        ng "F: fundrawtransaction emitted nVersion $FV"
    fi
    if [ "$SENT_OK" = 1 ]; then
        ok "F: the funded transaction is accepted: $SENT"
    else
        ng "F: the funded transaction is rejected: $(echo "$SENT" | tr '\n' ' ')"
    fi
    if [ "$PV" = "$MARKER_DEC" ]; then
        ok "F: walletcreatefundedpsbt emits nVersion $MARKER_DEC after activation"
    else
        ng "F: walletcreatefundedpsbt emitted nVersion $PV"
    fi
else
    note "createrawtransaction + fundrawtransaction: nVersion $FV"
    if [ "$SENT_OK" = 1 ]; then
        note "sendrawtransaction of that transaction: accepted, txid $SENT"
    else
        note "sendrawtransaction of that transaction: rejected: $(echo "$SENT" | tr '\n' ' ' | sed 's/  */ /g')"
    fi
    note "walletcreatefundedpsbt: nVersion $PV"
    if [ "$FV" != "$MARKER_DEC" ]; then
        PATCHED="${MARKER_HEX_LE}${FUND:8}"
        PSIGNED=$(a signrawtransactionwithwallet "$PATCHED" | j 'd["hex"]')
        if PSENT=$(a sendrawtransaction "$PSIGNED" 2>&1); then
            note "version bytes patched to $MARKER_HEX_LE before signing: accepted, txid $PSENT"
        else
            note "version bytes patched before signing: rejected: $(echo "$PSENT" | tr '\n' ' ')"
        fi
    fi
fi
# The marker set before funding must survive funding, in both modes: the
# workaround published with v1.1.0-rc1 sets it there. Only the marker is
# checked. On a tree that carries the wallet's version through
# FundTransaction(), a caller that sets 2 cannot be told apart from the
# default and gets the wallet's version instead.
RAW2=$(a createrawtransaction '[]' "[{\"$AA\":1}]")
FUND2=$(a fundrawtransaction "${MARKER_HEX_LE}${RAW2:8}" | j 'd["hex"]')
FV2=$(a decoderawtransaction "$FUND2" | j 'd["version"]')
if [ "$FV2" = "$MARKER_DEC" ]; then
    ok "F: the marker set before fundrawtransaction survives funding"
    SIGNED2=$(a signrawtransactionwithwallet "$FUND2" | j 'd["hex"]')
    if SENT2=$(a sendrawtransaction "$SIGNED2" 2>&1); then
        ok "F: that transaction is accepted: $SENT2"
    else
        ng "F: that transaction is rejected: $(echo "$SENT2" | tr '\n' ' ')"
    fi
else
    ng "F: the marker set before fundrawtransaction was replaced by $FV2"
fi
CV=$(version_of a "$(a sendtoaddress "$AA" 1)")
if [ "$CV" = "$MARKER_DEC" ]; then
    ok "control: sendtoaddress after activation emits nVersion $MARKER_DEC"
else
    ng "control: sendtoaddress after activation emitted nVersion $CV"
fi

# ------------------------------------------------------------------ C (mixed mode)
if [ -n "$BUILD_B" ] && [ "$RESIDUE" = 1 ]; then
    echo
    echo "== C: A mines three more blocks after P; B (BUILD_B) follows each =="
    H0=$(a getblockcount)
    for k in 1 2 3; do
        BHC=$(mine a 1 "$AA")
        NTX=$(a getblock "$BHC" | j 'len(d["tx"])')
        HAS_T=$(a getblock "$BHC" | j "\"$T\" in d[\"tx\"]")
        if wait_height b $((H0 + k)) 60 && [ "$(b getbestblockhash)" = "$BHC" ] && [ "$HAS_T" = False ]; then
            ok "C: B follows A to block $((H0 + k)) ($NTX transactions, T not among them)"
        else
            ng "C: block $((H0 + k)): B at $(b getblockcount), tip $(b getbestblockhash); T in the block: $HAS_T"
        fi
    done
    if [ "$(b getconnectioncount)" = 1 ] && [ "$(a getconnectioncount)" = 1 ]; then
        ok "C: A and B are still connected"
    else
        ng "C: connections A=$(a getconnectioncount) B=$(b getconnectioncount)"
    fi
    MA=$(grep -c 'Misbehaving' "$LOGA" || true)
    MB=$(grep -c 'Misbehaving' "$LOGB" || true)
    if [ "${MA:-0}" = 0 ] && [ "${MB:-0}" = 0 ]; then
        ok "C: no Misbehaving entry on A or on B"
    else
        ng "C: Misbehaving entries: A $MA, B $MB"
    fi
    if b getmempoolentry "$T" >/dev/null 2>&1; then
        note "C: T is still in B's mempool at tip $(b getblockcount)"
    else
        note "C: T is no longer in B's mempool at tip $(b getblockcount)"
    fi
    note "C: A's mempool holds $(a getmempoolinfo | j 'd["size"]') transaction(s) at tip $(a getblockcount)"
fi

# ------------------------------------------------------------------ summary
echo
echo "== summary =="
echo "  PASS $PASS  FAIL $FAIL  INCONCLUSIVE $INCONCLUSIVE"
echo "# finished $(date -Iseconds)"
if [ "$FAIL" -eq 0 ] && [ "$INCONCLUSIVE" -eq 0 ]; then
    echo "  RESULT: ALL CHECKS PASSED"
    exit 0
fi
echo "  RESULT: see FAIL / INCONCLUSIVE above"
exit 1
