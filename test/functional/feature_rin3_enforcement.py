#!/usr/bin/env python3
# Copyright (c) 2026 Core Authority / Rincoin Developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

"""
feature_rin3_enforcement.py

Rincoin RIN3 (nVersion replay protection) — consensus-level enforcement tests.

Activation:
    nRinHashForkHeight (regtest) = 840
    At height >= fork, ContextualCheckBlock rejects any non-exempt tx whose
    nVersion != RIN_FORK_TX_VERSION (0x52494e33) with "bad-tx-rinhash-version".
    Exempt: coinbase, HogEx, MWEBOnly.

Test matrix (in execution order):
    [01] Pre-fork  : legacy tx in block at h=839  → ACCEPT  (no enforcement)
    [02] At  fork  : nVersion=2  block at h=840   → REJECT
    [03] At  fork  : nVersion=1  block at h=840   → REJECT
    [04] At  fork  : nVersion=3  block at h=840   → REJECT  (above MAX_STANDARD, not RIN3)
    [05] At  fork  : mixed RIN3+legacy at h=840   → REJECT  (whole block invalid)
    [06] At  fork  : pure RIN3 tx at h=840        → ACCEPT  (positive control, advances chain)
    [07] Post-fork : legacy tx at h=841           → REJECT
    [08] Mempool   : nVersion=3 via sendrawtransaction at h=841 → REJECT (IsStandardTx)

Out of scope (require MWEB activation):
    - HogEx exemption
    - MWEBOnly exemption
"""

import io

from test_framework.test_framework import BitcoinTestFramework
from test_framework.messages import (
    CTransaction, CTxIn, CTxOut, COutPoint, COIN,
)
from test_framework.blocktools import create_block, create_coinbase
from test_framework.util import assert_equal, assert_raises_rpc_error

RIN_FORK_TX_VERSION = 0x52494e33   # "RIN3" ASCII = 1380535859
FORK_HEIGHT = 840                  # regtest nRinHashForkHeight


class Rin3EnforcementTest(BitcoinTestFramework):

    def set_test_params(self):
        self.num_nodes = 1
        self.setup_clean_chain = True
        self.extra_args = [["-fallbackfee=0.001", "-acceptnonstdtxn=0"]]

    def skip_test_if_missing_module(self):
        self.skip_if_no_wallet()

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _pick_utxo(self):
        """Return any mature spendable UTXO."""
        utxos = self.nodes[0].listunspent()
        assert len(utxos) > 0, "no mature UTXOs available"
        return utxos[0]

    def _build_signed_tx(self, nversion, utxo=None, fee_sat=1000):
        """
        Build and sign a tx with a specific nVersion, paying to a dummy P2WPKH.

        signrawtransactionwithwallet does NOT invoke txassembler, so the
        wallet does NOT overwrite nVersion. We still assert it post-sign.
        """
        node = self.nodes[0]
        utxo = utxo or self._pick_utxo()

        tx = CTransaction()
        tx.nVersion = nversion
        tx.vin.append(CTxIn(COutPoint(int(utxo["txid"], 16), utxo["vout"]), b""))
        # P2WPKH to all-zero pubkey hash (unspendable burn)
        tx.vout.append(CTxOut(
            int(utxo["amount"] * COIN) - fee_sat,
            bytes.fromhex("0014" + "00" * 20),
        ))

        signed_hex = node.signrawtransactionwithwallet(tx.serialize().hex())["hex"]

        # Confirm wallet preserved nVersion
        check = CTransaction()
        check.deserialize(io.BytesIO(bytes.fromhex(signed_hex)))
        assert check.nVersion == nversion, (
            f"wallet overwrote nVersion: {nversion:#x} -> {check.nVersion:#x}"
        )
        return check

    def _build_block(self, extra_txs):
        """Build a block at current_tip + 1 containing the given extra txs."""
        node = self.nodes[0]
        tip_hash = node.getbestblockhash()
        tip_height = node.getblockcount()
        block_time = node.getblock(tip_hash)["time"] + 1

        block = create_block(
            int(tip_hash, 16),
            create_coinbase(tip_height + 1),
            block_time,
        )
        for tx in extra_txs:
            block.vtx.append(tx)
        block.hashMerkleRoot = block.calc_merkle_root()
        block.solve()
        return block

    def _submit_expect_reject(self, block, label, expected_substring="rinhash"):
        node = self.nodes[0]
        h_before = node.getblockcount()
        result = node.submitblock(block.serialize().hex())
        self.log.info(f"  {label}: submitblock → {result!r}")

        assert result is not None, f"{label}: block unexpectedly ACCEPTED"
        assert expected_substring in str(result).lower(), (
            f"{label}: unexpected reject reason: {result}"
        )
        assert_equal(node.getblockcount(), h_before)
        self.log.info(f"  [PASS] {label}")

    def _submit_expect_accept(self, block, label):
        node = self.nodes[0]
        h_before = node.getblockcount()
        result = node.submitblock(block.serialize().hex())
        self.log.info(f"  {label}: submitblock → {result!r}")

        assert result is None, f"{label}: block unexpectedly REJECTED: {result}"
        assert_equal(node.getblockcount(), h_before + 1)
        self.log.info(f"  [PASS] {label}")

    # ------------------------------------------------------------------
    # Subtests
    # ------------------------------------------------------------------

    def subtest_01_pre_fork_legacy_accepted(self):
        """Legacy tx in a block at h=839 must be accepted (no enforcement yet)."""
        self.log.info("[01] Pre-fork: legacy tx at h=839 should be accepted")
        node = self.nodes[0]
        addr = node.getnewaddress()

        # Build chain to h=838
        node.generatetoaddress(838, addr)
        assert_equal(node.getblockcount(), 838)

        # Need a mature UTXO; coinbase at h=1 should be mature after 100 confs (h>=101)
        legacy_tx = self._build_signed_tx(nversion=2)
        block = self._build_block([legacy_tx])
        self._submit_expect_accept(block, "block at h=839 with nVersion=2")

    def subtest_02_at_fork_v2_rejected(self):
        """nVersion=2 user tx at h=840 must be rejected."""
        self.log.info("[02] At-fork: nVersion=2 should be rejected at h=840")
        assert_equal(self.nodes[0].getblockcount(), 839)
        bad_tx = self._build_signed_tx(nversion=2)
        block = self._build_block([bad_tx])
        self._submit_expect_reject(block, "nVersion=2 at h=840")

    def subtest_03_at_fork_v1_rejected(self):
        """nVersion=1 user tx at h=840 must be rejected."""
        self.log.info("[03] At-fork: nVersion=1 should be rejected at h=840")
        bad_tx = self._build_signed_tx(nversion=1)
        block = self._build_block([bad_tx])
        self._submit_expect_reject(block, "nVersion=1 at h=840")

    def subtest_04_at_fork_v3_rejected(self):
        """nVersion=3 (above MAX_STANDARD, not RIN3) must be rejected at h=840."""
        self.log.info("[04] At-fork: nVersion=3 should be rejected at h=840")
        bad_tx = self._build_signed_tx(nversion=3)
        block = self._build_block([bad_tx])
        self._submit_expect_reject(block, "nVersion=3 at h=840")

    def subtest_05_at_fork_mixed_block_rejected(self):
        """Block with one good RIN3 tx and one legacy tx must be rejected entirely."""
        self.log.info("[05] At-fork: mixed block (RIN3 + legacy) should be rejected")
        utxos = self.nodes[0].listunspent()
        assert len(utxos) >= 2, "need two UTXOs for mixed block"

        good_tx = self._build_signed_tx(nversion=RIN_FORK_TX_VERSION, utxo=utxos[0])
        bad_tx  = self._build_signed_tx(nversion=2,                   utxo=utxos[1])

        block = self._build_block([good_tx, bad_tx])
        self._submit_expect_reject(block, "mixed RIN3+legacy at h=840")

    def subtest_06_at_fork_rin3_accepted(self):
        """Positive control: pure RIN3 block at h=840 must be accepted."""
        self.log.info("[06] At-fork: RIN3 tx should be accepted (positive control)")
        good_tx = self._build_signed_tx(nversion=RIN_FORK_TX_VERSION)
        block = self._build_block([good_tx])
        self._submit_expect_accept(block, "RIN3 tx at h=840")
        assert_equal(self.nodes[0].getblockcount(), 840)

    def subtest_07_post_fork_legacy_rejected(self):
        """nVersion=2 tx at h=841 (after first fork block) must be rejected."""
        self.log.info("[07] Post-fork: nVersion=2 should be rejected at h=841")
        assert_equal(self.nodes[0].getblockcount(), 840)
        bad_tx = self._build_signed_tx(nversion=2)
        block = self._build_block([bad_tx])
        self._submit_expect_reject(block, "nVersion=2 at h=841")

    def subtest_08_mempool_rejects_nversion3(self):
        """nVersion=3 via sendrawtransaction must be rejected at mempool (IsStandardTx)."""
        self.log.info("[08] Mempool: nVersion=3 should be rejected by IsStandardTx")
        # We're at h=840; the mempool's standardness check rejects unknown versions.
        bad_tx = self._build_signed_tx(nversion=3)
        assert_raises_rpc_error(
            -26, "version",
            self.nodes[0].sendrawtransaction, bad_tx.serialize().hex()
        )
        self.log.info("  [PASS] mempool rejected nVersion=3 with 'version' reason")

    # ------------------------------------------------------------------
    # Driver
    # ------------------------------------------------------------------

    def run_test(self):
        self.log.info("=" * 60)
        self.log.info("RIN3 nVersion enforcement — consensus & mempool tests")
        self.log.info(f"nRinHashForkHeight (regtest) = {FORK_HEIGHT}")
        self.log.info(f"RIN_FORK_TX_VERSION = {hex(RIN_FORK_TX_VERSION)} "
                      f"= {RIN_FORK_TX_VERSION}")
        self.log.info("=" * 60)

        self.subtest_01_pre_fork_legacy_accepted()
        self.subtest_02_at_fork_v2_rejected()
        self.subtest_03_at_fork_v1_rejected()
        self.subtest_04_at_fork_v3_rejected()
        self.subtest_05_at_fork_mixed_block_rejected()
        self.subtest_06_at_fork_rin3_accepted()
        self.subtest_07_post_fork_legacy_rejected()
        self.subtest_08_mempool_rejects_nversion3()

        self.log.info("=" * 60)
        self.log.info("ALL SUBTESTS PASSED")
        self.log.info("RIN3 consensus-layer defense verified end-to-end")
        self.log.info("=" * 60)


if __name__ == "__main__":
    Rin3EnforcementTest().main()
