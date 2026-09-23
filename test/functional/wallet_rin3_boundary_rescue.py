#!/usr/bin/env python3
# Copyright (c) 2026 The Rincoin Core developers
# Distributed under the MIT software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.

"""
wallet_rin3_boundary_rescue.py

Rincoin RIN3 (nVersion replay protection) -- a legacy-version transaction
that was broadcast before the fork height and did not confirm.

From the fork height a transaction with nVersion 2 is never mined again, but
a mempool that accepted one before the fork keeps it: block assembly skips
it, and nothing in the fork rule removes it. It stays until it expires
(-mempoolexpiry, 336 hours by default), is evicted to make room, is
conflicted by a transaction in a connected block, or the node restarts. On
this tree the mempool also refuses a replacement by default, so while a node
holds such a transaction it refuses any other transaction that spends the
same inputs. A restart drops it: LoadMempool() runs every saved transaction
through mempool acceptance again, and from the fork height the legacy
version is refused there.

The replacement policy is inherited from Litecoin. Bitcoin Core v0.21.2
honours BIP 125 signalling unconditionally (validation.cpp,
fReplacementOptOut). Litecoin gates the same check on -mempoolreplacement
("Litecoin: Only support BIP125 RBF when -mempoolreplacement arg is set")
with DEFAULT_ENABLE_REPLACEMENT false in validation.h, so a conflicting
transaction is refused with txn-mempool-conflict whether or not the one it
conflicts with signalled. This tree carries that unchanged.

Two nodes: node0 holds the wallet that sent the transactions, node1 mines.

Test matrix (regtest fork height 840):
    [01] tip 838 : node0 sends A (BIP 125) and B (not)  -> nVersion 2, in both
                   mempools
    [02] tip 839 : node1 mines block 839 without them   -> still in both
    [03] tip 840 : node1 mines block 840                -> block assembly skips
                   a legacy version; still in both
    [04] node0   : abandontransaction(A)                -> refused, A is in the
                   mempool
                   bumpfee(A)                           -> R_A carries the marker,
                   but the default policy refuses a replacement
                   (txn-mempool-conflict), so A stays and R_A does not enter
    [05] node0   : bumpfee(B)                           -> refused, not BIP 125
    [06] node0   : restart                              -> LoadMempool() reports
                   the two saved transactions as failed; the wallet re-adds
                   R_A on its own; B is abandoned and re-created from its own
                   inputs through fundrawtransaction as R_B, with the marker
    [07] node1   : still holds A and B                  -> refuses R_A and R_B
                   (txn-mempool-conflict)
    [08] node1   : restart                              -> LoadMempool() reports
                   the two as failed; R_A and R_B are then accepted
    [09] tip 841 : node1 mines block 841                -> R_A and R_B are in it,
                   A and B are not; the wallet shows A and B as conflicted
                   by them

R_A goes through CreateTransaction() via bumpfee. R_B goes through
CWallet::FundTransaction() via fundrawtransaction, so this test relies on
that function carrying the version (wallet_rin3_fund_version.py covers it).
"""

import time

from test_framework.messages import COIN
from test_framework.test_framework import BitcoinTestFramework
from test_framework.util import assert_equal, assert_raises_rpc_error

RIN_FORK_TX_VERSION = 0x52494e33   # "RIN3" ASCII = 1380535859
LEGACY_TX_VERSION   = 2            # CTransaction::CURRENT_VERSION
FORK_HEIGHT         = 840          # regtest nRinHashForkHeight


class WalletRin3BoundaryRescueTest(BitcoinTestFramework):

    def set_test_params(self):
        self.num_nodes = 2
        self.setup_clean_chain = True
        args = [
            "-fallbackfee=0.001",
            "-acceptnonstdtxn=0",
            # Disable MWEB for this test, as feature_rin3_enforcement.py does:
            # a far-future timestamp (~2286) stands in for NEVER_ACTIVE.
            "-vbparams=mweb:9999999999:9999999999",
            # Relay without the trickle delay, as rpc_fundrawtransaction.py
            # does. The permission applies to inbound peers, so node1 always
            # connects to node0 (as setup_network does), and node0 announces
            # to node1 without waiting.
            "-whitelist=noban@127.0.0.1",
        ]
        self.extra_args = [args, args]

    def skip_test_if_missing_module(self):
        self.skip_if_no_wallet()

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _wait_for(self, predicate, what: str, timeout: int = 30):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if predicate():
                return
            time.sleep(0.25)
        raise AssertionError(f"timed out after {timeout}s waiting for {what}")

    def _wait_for_mempool_loaded(self, node):
        self._wait_for(lambda: node.getmempoolinfo()["loaded"], "mempool to load")

    def _restart_and_expect_saved_refused(self, i: int, saved: int):
        """Restart node i and check LoadMempool()'s report: every one of the
        `saved` transactions is refused on load (it runs them through mempool
        acceptance again, where the legacy version fails from the fork
        height)."""
        node = self.nodes[i]
        with node.assert_debug_log(
                [f"Imported mempool transactions from disk: 0 succeeded, {saved} failed"],
                timeout=30):
            self.restart_node(i)
            self._wait_for_mempool_loaded(node)

    def _wallet_hex(self, txid: str) -> str:
        return self.nodes[0].gettransaction(txid)["hex"]

    def _version_of(self, txid: str) -> int:
        return self.nodes[0].decoderawtransaction(self._wallet_hex(txid))["version"]

    def _send(self, replaceable: bool) -> str:
        """sendtoaddress from node0 with BIP 125 signalling set explicitly."""
        node = self.nodes[0]
        return node.sendtoaddress(node.getnewaddress(), 1, "", "", False, replaceable)

    def _mine_on_node1_without(self, txids) -> str:
        """node1 mines one block; check that none of `txids` is in it and that
        both mempools still hold all of them."""
        miner = self.nodes[1]
        block_hash = miner.generatetoaddress(1, miner.getnewaddress())[0]
        self.sync_blocks()
        block_txs = miner.getblock(block_hash)["tx"]
        for txid in txids:
            assert txid not in block_txs
            for node in self.nodes:
                assert txid in node.getrawmempool()
        return block_hash

    # ------------------------------------------------------------------
    # Subtests
    # ------------------------------------------------------------------

    def subtest_01_two_legacy_transactions(self):
        self.log.info("[01] tip 838: node0 sends a BIP 125 transaction and one that "
                      "does not signal")
        node0, node1 = self.nodes
        self.log.info(f"  Mining from h=0 to h={FORK_HEIGHT - 2} on node0 ...")
        node0.generatetoaddress(FORK_HEIGHT - 2, node0.getnewaddress())
        self.sync_blocks()

        self.tx_a = self._send(replaceable=True)
        self.tx_b = self._send(replaceable=False)
        for name, txid in (("A", self.tx_a), ("B", self.tx_b)):
            version = self._version_of(txid)
            self.log.info(f"  {name} {txid[:16]}...  nVersion = {version}")
            assert_equal(version, LEGACY_TX_VERSION)
        self.sync_mempools()
        assert_equal(node1.getmempoolinfo()["size"], 2)

        # Keep both out of the next block on the miner: a large negative fee
        # delta puts them below the block assembler's minimum fee rate.
        for txid in (self.tx_a, self.tx_b):
            node1.prioritisetransaction(txid=txid, fee_delta=-COIN)

    def subtest_02_block_839_without_them(self):
        self.log.info("[02] node1 mines block 839 without them; both mempools keep them")
        self._mine_on_node1_without([self.tx_a, self.tx_b])
        assert_equal(self.nodes[0].getblockcount(), FORK_HEIGHT - 1)

    def subtest_03_block_840_skips_them(self):
        self.log.info("[03] block 840 skips a legacy version; both mempools keep them")
        node1 = self.nodes[1]
        # From here on the negative delta is not what keeps them out: block
        # assembly does not take a legacy version at or after the fork height.
        for txid in (self.tx_a, self.tx_b):
            node1.prioritisetransaction(txid=txid, fee_delta=COIN)
        self._mine_on_node1_without([self.tx_a, self.tx_b])
        assert_equal(self.nodes[0].getblockcount(), FORK_HEIGHT)
        assert_equal(node1.getblockstats(FORK_HEIGHT)["subsidy"], 400000000)

    def subtest_04_bumpfee_is_refused_by_policy(self):
        self.log.info("[04] node0: A cannot be abandoned; bumpfee builds a marker replacement "
                      "the default policy refuses")
        node0 = self.nodes[0]
        # RPC_INVALID_ADDRESS_OR_KEY (-5) is what abandontransaction raises here.
        assert_raises_rpc_error(-5, "Transaction not eligible for abandonment",
                                node0.abandontransaction, self.tx_a)

        with node0.assert_debug_log(
                ["Transaction cannot be broadcast immediately, txn-mempool-conflict"]):
            res = node0.bumpfee(self.tx_a)
        assert_equal(res["errors"], [])
        self.tx_ra = res["txid"]
        version = self._version_of(self.tx_ra)
        self.log.info(f"  R_A {self.tx_ra[:16]}...  nVersion = {version} ({version:#010x})")
        assert_equal(version, RIN_FORK_TX_VERSION)
        mempool = node0.getrawmempool()
        assert self.tx_ra not in mempool
        assert self.tx_a in mempool

    def subtest_05_bumpfee_b_refused(self):
        self.log.info("[05] node0: B does not signal BIP 125 and cannot be bumped")
        assert_raises_rpc_error(-4, "not BIP 125 replaceable",
                                self.nodes[0].bumpfee, self.tx_b)

    def subtest_06_restart_node0(self):
        self.log.info("[06] node0 restarts: the saved A and B fail to load; the wallet "
                      "re-adds R_A; B is re-created from its inputs")
        self._restart_and_expect_saved_refused(0, saved=2)
        node0 = self.nodes[0]
        assert_equal(node0.getconnectioncount(), 0)
        mempool = node0.getrawmempool()
        assert self.tx_a not in mempool
        assert self.tx_b not in mempool

        # On load the wallet resubmits its unconfirmed transactions
        # (ReacceptWalletTransactions). A and B are refused; R_A is accepted.
        self._wait_for(lambda: self.tx_ra in node0.getrawmempool(),
                       "the wallet to re-add R_A")

        # B is no longer in the mempool, so it can be abandoned. Re-create it
        # from the same inputs, so that it conflicts with B wherever B remains.
        node0.abandontransaction(self.tx_b)
        b_vin = node0.decoderawtransaction(self._wallet_hex(self.tx_b))["vin"]
        inputs = [{"txid": i["txid"], "vout": i["vout"]} for i in b_vin]
        raw = node0.createrawtransaction(inputs, [{node0.getnewaddress(): 1}])
        funded = node0.fundrawtransaction(raw)["hex"]
        version = node0.decoderawtransaction(funded)["version"]
        self.log.info(f"  R_B funded  nVersion = {version} ({version:#010x})")
        assert_equal(version, RIN_FORK_TX_VERSION)
        signed = node0.signrawtransactionwithwallet(funded)
        assert_equal(signed["complete"], True)
        self.tx_rb = node0.sendrawtransaction(signed["hex"])
        assert self.tx_rb in node0.getrawmempool()

    def subtest_07_node1_refuses_the_rescue(self):
        self.log.info("[07] node1 still holds A and B and refuses R_A and R_B")
        node0, node1 = self.nodes
        self.connect_nodes(1, 0)
        with node1.assert_debug_log([
                f"{self.tx_ra} from peer",
                f"{self.tx_rb} from peer",
                "was not accepted: txn-mempool-conflict"], timeout=30):
            node0.sendrawtransaction(self._wallet_hex(self.tx_ra))
            node0.sendrawtransaction(self._wallet_hex(self.tx_rb))
        mempool = node1.getrawmempool()
        assert self.tx_a in mempool
        assert self.tx_b in mempool
        assert self.tx_ra not in mempool
        assert self.tx_rb not in mempool

    def subtest_08_restart_node1(self):
        self.log.info("[08] node1 restarts: the saved A and B fail to load; "
                      "R_A and R_B are accepted")
        node0 = self.nodes[0]
        self._restart_and_expect_saved_refused(1, saved=2)
        node1 = self.nodes[1]
        mempool = node1.getrawmempool()
        assert self.tx_a not in mempool
        assert self.tx_b not in mempool

        self.connect_nodes(1, 0)
        node0.sendrawtransaction(self._wallet_hex(self.tx_ra))
        node0.sendrawtransaction(self._wallet_hex(self.tx_rb))
        self._wait_for(lambda: {self.tx_ra, self.tx_rb} <= set(node1.getrawmempool()),
                       "R_A and R_B in node1's mempool")

    def subtest_09_block_841(self):
        self.log.info("[09] node1 mines block 841: R_A and R_B are in it, A and B are not "
                      "and show as conflicted")
        node0, node1 = self.nodes
        block_hash = node1.generatetoaddress(1, node1.getnewaddress())[0]
        self.sync_blocks()
        assert_equal(node0.getblockcount(), FORK_HEIGHT + 1)
        block_txs = node1.getblock(block_hash)["tx"]
        assert self.tx_ra in block_txs
        assert self.tx_rb in block_txs
        assert self.tx_a not in block_txs
        assert self.tx_b not in block_txs
        assert_equal(node0.gettransaction(self.tx_ra)["confirmations"], 1)
        assert_equal(node0.gettransaction(self.tx_rb)["confirmations"], 1)
        for node in self.nodes:
            assert_equal(node.getmempoolinfo()["size"], 0)

        # The wallet's view: A and B are conflicted by the transactions that
        # spent their inputs, and A records what replaced it.
        tx_a_info = node0.gettransaction(self.tx_a)
        tx_b_info = node0.gettransaction(self.tx_b)
        assert_equal(tx_a_info["confirmations"], -1)
        assert_equal(tx_b_info["confirmations"], -1)
        assert self.tx_ra in tx_a_info["walletconflicts"]
        assert self.tx_rb in tx_b_info["walletconflicts"]
        assert_equal(tx_a_info["replaced_by_txid"], self.tx_ra)
        assert_equal(node0.gettransaction(self.tx_ra)["replaces_txid"], self.tx_a)

    # ------------------------------------------------------------------

    def run_test(self):
        self.log.info("=" * 55)
        self.log.info("  RIN3 boundary -- a stuck legacy transaction")
        self.log.info(f"  nRinHashForkHeight (regtest) = {FORK_HEIGHT}")
        self.log.info(f"  RIN_FORK_TX_VERSION = {RIN_FORK_TX_VERSION:#010x}"
                      f" = {RIN_FORK_TX_VERSION}")
        self.log.info("=" * 55)

        self.subtest_01_two_legacy_transactions()
        self.subtest_02_block_839_without_them()
        self.subtest_03_block_840_skips_them()
        self.subtest_04_bumpfee_is_refused_by_policy()
        self.subtest_05_bumpfee_b_refused()
        self.subtest_06_restart_node0()
        self.subtest_07_node1_refuses_the_rescue()
        self.subtest_08_restart_node1()
        self.subtest_09_block_841()

        self.log.info("=" * 55)
        self.log.info("  ALL 9 SUBTESTS PASSED")
        self.log.info("  a node that holds a pre-fork legacy transaction refuses its")
        self.log.info("  re-creation until it restarts, when LoadMempool() drops the")
        self.log.info("  legacy one; after that the re-creations confirm")
        self.log.info("=" * 55)


if __name__ == "__main__":
    WalletRin3BoundaryRescueTest().main()
