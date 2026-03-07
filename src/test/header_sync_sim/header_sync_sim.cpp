/*
 * Header Sync Simulator — standalone test for Rincoin header-processing
 * performance experiments.
 *
 * Copyright (c) 2025 The Rincoin developers
 * MIT licence — see COPYING
 *
 * -----------------------------------------------------------------------
 *
 * This program simulates the hot-path of Initial Block Download (IBD),
 * specifically the ProcessNewBlockHeaders → AcceptBlockHeader pipeline,
 * WITHOUT requiring any networking, disk I/O, or full-node context.
 *
 * It generates synthetic but realistic block headers, then benchmarks
 * four strategies:
 *
 *   Strategy 0  — Baseline (current code)
 *       4× RinHash per new header, single-threaded, single global lock.
 *
 *   Strategy 1  — Hash-cache only
 *       1× RinHash per header, result passed down; all other calls reuse it.
 *
 *   Strategy 2  — Parallel PoW only
 *       PoW hashing done in a thread pool, index insertion still serial.
 *
 *   Strategy 3  — Parallel PoW + hash cache (combined)
 *       Best of both worlds.
 *
 * Build:  make -C src/test/header_sync_sim -j$(nproc)
 * Run  :  ./src/test/header_sync_sim/header_sync_sim [num_headers] [batch_sz]
 */

#include <cstdint>
#include <cstring>
#include <chrono>
#include <iostream>
#include <iomanip>
#include <vector>
#include <unordered_map>
#include <thread>
#include <mutex>
#include <atomic>
#include <functional>
#include <condition_variable>
#include <queue>
#include <random>
#include <cassert>
#include <cstdio>

/* --------------------------------------------------------------------------
 *  Minimal uint256 — just enough to be a map key and hold 32 bytes
 * ------------------------------------------------------------------------ */

struct uint256 {
    uint8_t data[32]{};

    uint256() = default;
    explicit uint256(const uint8_t* src) { std::memcpy(data, src, 32); }

    bool operator==(const uint256& o) const { return std::memcmp(data, o.data, 32) == 0; }
    bool operator!=(const uint256& o) const { return !(*this == o); }
    bool IsNull() const {
        for (int i = 0; i < 32; ++i) if (data[i]) return false;
        return true;
    }
    void SetNull() { std::memset(data, 0, 32); }
};

struct uint256_hash {
    size_t operator()(const uint256& v) const {
        /* FNV-1a over the first 16 bytes is plenty for a hash-map key */
        size_t h = 14695981039346656037ULL;
        for (int i = 0; i < 16; ++i)
            h = (h ^ v.data[i]) * 1099511628211ULL;
        return h;
    }
};

/* --------------------------------------------------------------------------
 *  Minimal block-header structure (matches CBlockHeader serialisation)
 * ------------------------------------------------------------------------ */

#pragma pack(push, 1)
struct BlockHeader {
    int32_t  nVersion{1};
    uint256  hashPrevBlock;
    uint256  hashMerkleRoot;
    uint32_t nTime{0};
    uint32_t nBits{0x1e0fffff};  /* regtest-style easy target */
    uint32_t nNonce{0};
};
#pragma pack(pop)

static_assert(sizeof(BlockHeader) == 4 + 32 + 32 + 4 + 4 + 4, "Packed header check");

/* --------------------------------------------------------------------------
 *  RinHash — BLAKE3 → Argon2d → SHA3-256   (the real algorithm)
 * ------------------------------------------------------------------------ */

extern "C" {
#include "blake3.h"
#include "argon2.h"
}
#include "sha3_standalone.h"   /* thin wrapper — see below */

static uint256 RinHash(const BlockHeader& hdr) {
    const uint8_t* raw = reinterpret_cast<const uint8_t*>(&hdr);
    constexpr size_t len = sizeof(BlockHeader);

    /* Step 1: BLAKE3 */
    uint8_t blake3_out[32];
    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, raw, len);
    blake3_hasher_finalize(&hasher, blake3_out, 32);

    /* Step 2: Argon2d (t=2, m=64 KiB, p=1) */
    const char* salt = "RinCoinSalt";
    uint8_t argon2_out[32];
    argon2_context ctx{};
    ctx.out     = argon2_out;
    ctx.outlen  = 32;
    ctx.pwd     = blake3_out;
    ctx.pwdlen  = 32;
    ctx.salt    = (uint8_t*)salt;
    ctx.saltlen = (uint32_t)strlen(salt);
    ctx.t_cost  = 2;
    ctx.m_cost  = 64;
    ctx.lanes   = 1;
    ctx.threads = 1;
    ctx.version = ARGON2_VERSION_13;
    ctx.allocate_cbk = nullptr;
    ctx.free_cbk     = nullptr;
    ctx.flags        = ARGON2_DEFAULT_FLAGS;

    int rc = argon2d_ctx(&ctx);
    if (rc != ARGON2_OK) {
        fprintf(stderr, "Argon2d failed: %d\n", rc);
        std::abort();
    }

    /* Step 3: SHA3-256 */
    uint8_t sha3_out[32];
    sha3_256(argon2_out, 32, sha3_out);

    return uint256(sha3_out);
}

/* --------------------------------------------------------------------------
 *  Minimal block-index (mirrors CBlockIndex: stores hash, height, pprev)
 * ------------------------------------------------------------------------ */

struct BlockIndex {
    const uint256* phashBlock{nullptr};   /* points into the map key */
    BlockIndex*    pprev{nullptr};
    int            nHeight{0};
    uint32_t       nBits{0};
    uint32_t       nTime{0};
};

using BlockMap = std::unordered_map<uint256, BlockIndex*, uint256_hash>;

/* --------------------------------------------------------------------------
 *  Simulated "Dark Gravity Wave" difficulty check (lightweight)
 * ------------------------------------------------------------------------ */
static bool CheckDifficulty(const BlockIndex* /*pindexPrev*/, const BlockHeader& /*hdr*/) {
    /* Real DGW reads 24 previous nBits — we stub it as always-pass here
       because the overhead is trivial (< 1 μs).  The simulator focuses
       on RinHash cost which dominates by orders of magnitude. */
    return true;
}

/* --------------------------------------------------------------------------
 *  Simple thread pool (fixed size, task queue, graceful shutdown)
 * ------------------------------------------------------------------------ */

class ThreadPool {
public:
    explicit ThreadPool(size_t n) {
        for (size_t i = 0; i < n; ++i)
            workers_.emplace_back([this] { worker_loop(); });
    }
    ~ThreadPool() { shutdown(); }

    void shutdown() {
        {
            std::lock_guard<std::mutex> lk(mu_);
            stop_ = true;
        }
        cv_.notify_all();
        for (auto& t : workers_) if (t.joinable()) t.join();
        workers_.clear();
    }

    /* Submit work; returns immediately. */
    void submit(std::function<void()> fn) {
        {
            std::lock_guard<std::mutex> lk(mu_);
            q_.push(std::move(fn));
        }
        cv_.notify_one();
    }

    /* Block until every submitted task has been executed. */
    void wait_idle() {
        std::unique_lock<std::mutex> lk(mu_);
        idle_cv_.wait(lk, [this]{
            return q_.empty() && active_ == 0;
        });
    }

private:
    void worker_loop() {
        for (;;) {
            std::function<void()> task;
            {
                std::unique_lock<std::mutex> lk(mu_);
                cv_.wait(lk, [this]{ return stop_ || !q_.empty(); });
                if (stop_ && q_.empty()) return;
                task = std::move(q_.front());
                q_.pop();
                ++active_;
            }
            task();
            {
                std::lock_guard<std::mutex> lk(mu_);
                --active_;
            }
            idle_cv_.notify_all();
        }
    }

    std::vector<std::thread>           workers_;
    std::queue<std::function<void()>>  q_;
    std::mutex                         mu_;
    std::condition_variable            cv_;
    std::condition_variable            idle_cv_;
    int                                active_{0};
    bool                               stop_{false};
};

/* ==========================================================================
 *  STRATEGY 0 — Baseline (mirrors current Rincoin code)
 *
 *  Per new header:
 *    1) hash = header.GetHash()       — RinHash #1  (continuity check)
 *    2) hash = block.GetHash()        — RinHash #2  (AcceptBlockHeader dup check)
 *    3) block.GetPoWHash()            — RinHash #3  (CheckBlockHeader PoW)
 *    4) hash = block.GetHash()        — RinHash #4  (AddToBlockIndex)
 * ========================================================================== */

struct BenchResult {
    int64_t total_us;
    int64_t continuity_us;
    int64_t accept_us;
    size_t  new_headers;
    size_t  dup_headers;
};

static BenchResult strategy0_baseline(
    const std::vector<BlockHeader>& batch,
    BlockMap& index,
    std::mutex& cs_main)
{
    auto t0 = std::chrono::steady_clock::now();
    int64_t continuity_us = 0;
    int64_t accept_us = 0;
    size_t new_count = 0, dup_count = 0;

    /* --- Phase 1: continuity check (under cs_main in real code) --- */
    {
        auto tc0 = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lk(cs_main);
        uint256 hashLast;
        for (auto& hdr : batch) {
            if (!hashLast.IsNull() && hdr.hashPrevBlock != hashLast) {
                fprintf(stderr, "Non-continuous header!\n"); std::abort();
            }
            hashLast = RinHash(hdr);          /* RinHash #1 */
        }
        auto tc1 = std::chrono::steady_clock::now();
        continuity_us = std::chrono::duration_cast<std::chrono::microseconds>(tc1 - tc0).count();
    }

    /* --- Phase 2: AcceptBlockHeader loop (under cs_main) --- */
    {
        auto ta0 = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lk(cs_main);
        for (auto& hdr : batch) {
            /* AcceptBlockHeader: duplicate check */
            uint256 hash = RinHash(hdr);      /* RinHash #2 */
            auto it = index.find(hash);
            if (it != index.end()) { dup_count++; continue; }

            /* CheckBlockHeader: PoW */
            uint256 pow = RinHash(hdr);       /* RinHash #3 */
            (void)pow; /* would compare against target */

            /* ContextualCheckBlockHeader — lightweight */
            BlockIndex* prev = nullptr;
            if (!hdr.hashPrevBlock.IsNull()) {
                auto pit = index.find(hdr.hashPrevBlock);
                if (pit != index.end()) prev = pit->second;
            }
            CheckDifficulty(prev, hdr);

            /* AddToBlockIndex */
            uint256 hash2 = RinHash(hdr);     /* RinHash #4 */
            auto* bi = new BlockIndex();
            bi->nHeight = prev ? prev->nHeight + 1 : 0;
            bi->nBits   = hdr.nBits;
            bi->nTime   = hdr.nTime;
            bi->pprev   = prev;
            auto ins = index.emplace(hash2, bi);
            bi->phashBlock = &ins.first->first;
            new_count++;
        }
        auto ta1 = std::chrono::steady_clock::now();
        accept_us = std::chrono::duration_cast<std::chrono::microseconds>(ta1 - ta0).count();
    }

    auto t1 = std::chrono::steady_clock::now();
    return {
        std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count(),
        continuity_us, accept_us, new_count, dup_count
    };
}

/* ==========================================================================
 *  STRATEGY 1 — Hash-cache: compute RinHash ONCE per header
 *
 *  Compute hash up-front, pass it to every consumer.
 * ========================================================================== */

static BenchResult strategy1_hash_cache(
    const std::vector<BlockHeader>& batch,
    BlockMap& index,
    std::mutex& cs_main)
{
    auto t0 = std::chrono::steady_clock::now();
    size_t new_count = 0, dup_count = 0;

    /* Pre-compute all hashes (single-threaded) */
    std::vector<uint256> hashes(batch.size());
    int64_t hash_us;
    {
        auto th0 = std::chrono::steady_clock::now();
        for (size_t i = 0; i < batch.size(); ++i)
            hashes[i] = RinHash(batch[i]);     /* Only RinHash call */
        auto th1 = std::chrono::steady_clock::now();
        hash_us = std::chrono::duration_cast<std::chrono::microseconds>(th1 - th0).count();
    }

    int64_t accept_us;
    {
        auto ta0 = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lk(cs_main);

        /* Continuity check using cached hashes — zero hashing */
        uint256 hashLast;
        for (size_t i = 0; i < batch.size(); ++i) {
            if (!hashLast.IsNull() && batch[i].hashPrevBlock != hashLast) {
                fprintf(stderr, "Non-continuous header!\n"); std::abort();
            }
            hashLast = hashes[i];
        }

        /* AcceptBlockHeader using cached hash */
        for (size_t i = 0; i < batch.size(); ++i) {
            const uint256& hash = hashes[i];
            auto it = index.find(hash);
            if (it != index.end()) { dup_count++; continue; }

            /* PoW check: reuse the same hash — no recomputation */
            /* (In real code, GetPoWHash() == GetHash() for Rincoin) */

            BlockIndex* prev = nullptr;
            if (!batch[i].hashPrevBlock.IsNull()) {
                auto pit = index.find(batch[i].hashPrevBlock);
                if (pit != index.end()) prev = pit->second;
            }
            CheckDifficulty(prev, batch[i]);

            auto* bi = new BlockIndex();
            bi->nHeight = prev ? prev->nHeight + 1 : 0;
            bi->nBits   = batch[i].nBits;
            bi->nTime   = batch[i].nTime;
            bi->pprev   = prev;
            auto ins = index.emplace(hash, bi);
            bi->phashBlock = &ins.first->first;
            new_count++;
        }
        auto ta1 = std::chrono::steady_clock::now();
        accept_us = std::chrono::duration_cast<std::chrono::microseconds>(ta1 - ta0).count();
    }

    auto t1 = std::chrono::steady_clock::now();
    return {
        std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count(),
        hash_us, accept_us, new_count, dup_count
    };
}

/* ==========================================================================
 *  STRATEGY 2 — Parallel PoW (no hash cache)
 *
 *  Hash computation happens in a thread pool *outside* cs_main.
 *  Index insertion is still serial under lock.
 *  Still 4× RinHash per header (but 3 of them are parallelised).
 * ========================================================================== */

static BenchResult strategy2_parallel_pow(
    const std::vector<BlockHeader>& batch,
    BlockMap& index,
    std::mutex& cs_main,
    ThreadPool& pool)
{
    auto t0 = std::chrono::steady_clock::now();
    size_t new_count = 0, dup_count = 0;

    /* Phase 1: parallel hashing for continuity check */
    std::vector<uint256> cont_hashes(batch.size());
    {
        for (size_t i = 0; i < batch.size(); ++i) {
            pool.submit([&, i]{
                cont_hashes[i] = RinHash(batch[i]);
            });
        }
        pool.wait_idle();
    }

    int64_t continuity_us;
    {
        auto tc0 = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lk(cs_main);
        uint256 hashLast;
        for (size_t i = 0; i < batch.size(); ++i) {
            if (!hashLast.IsNull() && batch[i].hashPrevBlock != hashLast) {
                fprintf(stderr, "Non-continuous header!\n"); std::abort();
            }
            hashLast = cont_hashes[i];
        }
        auto tc1 = std::chrono::steady_clock::now();
        continuity_us = std::chrono::duration_cast<std::chrono::microseconds>(tc1 - tc0).count();
    }

    /* Phase 2: parallel PoW hashing */
    std::vector<uint256> dup_hashes(batch.size());
    std::vector<uint256> pow_hashes(batch.size());
    std::vector<uint256> add_hashes(batch.size());
    {
        for (size_t i = 0; i < batch.size(); ++i) {
            pool.submit([&, i]{
                dup_hashes[i] = RinHash(batch[i]);
                pow_hashes[i] = RinHash(batch[i]);
                add_hashes[i] = RinHash(batch[i]);
            });
        }
        pool.wait_idle();
    }

    int64_t accept_us;
    {
        auto ta0 = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lk(cs_main);
        for (size_t i = 0; i < batch.size(); ++i) {
            auto it = index.find(dup_hashes[i]);
            if (it != index.end()) { dup_count++; continue; }

            (void)pow_hashes[i]; /* PoW check done */

            BlockIndex* prev = nullptr;
            if (!batch[i].hashPrevBlock.IsNull()) {
                auto pit = index.find(batch[i].hashPrevBlock);
                if (pit != index.end()) prev = pit->second;
            }
            CheckDifficulty(prev, batch[i]);

            auto* bi = new BlockIndex();
            bi->nHeight = prev ? prev->nHeight + 1 : 0;
            bi->nBits   = batch[i].nBits;
            bi->nTime   = batch[i].nTime;
            bi->pprev   = prev;
            auto ins = index.emplace(add_hashes[i], bi);
            bi->phashBlock = &ins.first->first;
            new_count++;
        }
        auto ta1 = std::chrono::steady_clock::now();
        accept_us = std::chrono::duration_cast<std::chrono::microseconds>(ta1 - ta0).count();
    }

    auto t1 = std::chrono::steady_clock::now();
    return {
        std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count(),
        continuity_us, accept_us, new_count, dup_count
    };
}

/* ==========================================================================
 *  STRATEGY 3 — Parallel PoW + hash cache (BEST)
 *
 *  1× RinHash per header, computed in parallel in a thread pool.
 *  Index insertion serial under lock, using pre-computed hashes.
 *  cs_main held ONLY for the lightweight index operations.
 * ========================================================================== */

static BenchResult strategy3_parallel_cache(
    const std::vector<BlockHeader>& batch,
    BlockMap& index,
    std::mutex& cs_main,
    ThreadPool& pool)
{
    auto t0 = std::chrono::steady_clock::now();
    size_t new_count = 0, dup_count = 0;

    /* Phase 1: parallel RinHash — ONE hash per header */
    std::vector<uint256> hashes(batch.size());
    int64_t hash_us;
    {
        auto th0 = std::chrono::steady_clock::now();
        for (size_t i = 0; i < batch.size(); ++i) {
            pool.submit([&, i]{
                hashes[i] = RinHash(batch[i]);
            });
        }
        pool.wait_idle();
        auto th1 = std::chrono::steady_clock::now();
        hash_us = std::chrono::duration_cast<std::chrono::microseconds>(th1 - th0).count();
    }

    /* Phase 2: serial index operations under cs_main */
    int64_t accept_us;
    {
        auto ta0 = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lk(cs_main);

        /* Continuity check */
        uint256 hashLast;
        for (size_t i = 0; i < batch.size(); ++i) {
            if (!hashLast.IsNull() && batch[i].hashPrevBlock != hashLast) {
                fprintf(stderr, "Non-continuous header!\n"); std::abort();
            }
            hashLast = hashes[i];
        }

        /* AcceptBlockHeader */
        for (size_t i = 0; i < batch.size(); ++i) {
            const uint256& hash = hashes[i];
            auto it = index.find(hash);
            if (it != index.end()) { dup_count++; continue; }

            /* PoW: same hash, no recomputation */

            BlockIndex* prev = nullptr;
            if (!batch[i].hashPrevBlock.IsNull()) {
                auto pit = index.find(batch[i].hashPrevBlock);
                if (pit != index.end()) prev = pit->second;
            }
            CheckDifficulty(prev, batch[i]);

            /* AddToBlockIndex */
            auto* bi = new BlockIndex();
            bi->nHeight = prev ? prev->nHeight + 1 : 0;
            bi->nBits   = batch[i].nBits;
            bi->nTime   = batch[i].nTime;
            bi->pprev   = prev;
            auto ins = index.emplace(hash, bi);
            bi->phashBlock = &ins.first->first;
            new_count++;
        }
        auto ta1 = std::chrono::steady_clock::now();
        accept_us = std::chrono::duration_cast<std::chrono::microseconds>(ta1 - ta0).count();
    }

    auto t1 = std::chrono::steady_clock::now();
    return {
        std::chrono::duration_cast<std::chrono::microseconds>(t1 - t0).count(),
        hash_us, accept_us, new_count, dup_count
    };
}

/* ==========================================================================
 *  Header generator — builds a chain of synthetic headers
 * ========================================================================== */

static std::vector<BlockHeader> generate_chain(size_t count) {
    std::vector<BlockHeader> chain;
    chain.reserve(count);

    std::mt19937 rng(42); /* deterministic for reproducibility */
    uint256 prevHash;
    prevHash.SetNull();

    for (size_t i = 0; i < count; ++i) {
        BlockHeader hdr;
        hdr.nVersion      = 0x20000000;
        hdr.hashPrevBlock = prevHash;
        /* Random merkle root */
        for (auto& b : hdr.hashMerkleRoot.data) b = (uint8_t)(rng() & 0xff);
        hdr.nTime  = (uint32_t)(1700000000 + i * 60);
        hdr.nBits  = 0x1e0fffff;
        hdr.nNonce = (uint32_t)(rng());

        chain.push_back(hdr);
        prevHash = RinHash(hdr);
    }
    return chain;
}

/* ==========================================================================
 *  Main — run all strategies and report
 * ========================================================================== */

int main(int argc, char* argv[])
{
    size_t total_headers = 20000;
    size_t batch_size    = 2000;

    if (argc >= 2) total_headers = (size_t)std::atoi(argv[1]);
    if (argc >= 3) batch_size    = (size_t)std::atoi(argv[2]);

    unsigned hw_threads = std::thread::hardware_concurrency();
    if (hw_threads == 0) hw_threads = 4;
    unsigned pool_size = std::max(2u, hw_threads - 1);

    printf("═══════════════════════════════════════════════════════════════════\n");
    printf("  Rincoin Header-Sync Simulator\n");
    printf("═══════════════════════════════════════════════════════════════════\n");
    printf("  Total headers : %zu\n", total_headers);
    printf("  Batch size    : %zu  (= MAX_HEADERS_RESULTS)\n", batch_size);
    printf("  HW threads    : %u  (pool will use %u)\n", hw_threads, pool_size);
    printf("  RinHash algo  : BLAKE3 → Argon2d(t=2,m=64KiB,p=1) → SHA3-256\n");
    printf("═══════════════════════════════════════════════════════════════════\n\n");

    /* --- Generate chain --- */
    printf("Generating %zu synthetic headers...\n", total_headers);
    auto gen0 = std::chrono::steady_clock::now();
    auto full_chain = generate_chain(total_headers);
    auto gen1 = std::chrono::steady_clock::now();
    double gen_s = std::chrono::duration<double>(gen1 - gen0).count();
    printf("  Done in %.2f s  (%.0f hdr/s)\n\n", gen_s, total_headers / gen_s);

    /* --- Split into batches --- */
    std::vector<std::vector<BlockHeader>> batches;
    for (size_t off = 0; off < full_chain.size(); off += batch_size) {
        size_t end = std::min(off + batch_size, full_chain.size());
        batches.emplace_back(full_chain.begin() + off, full_chain.begin() + end);
    }

    /* --- Run each strategy --- */
    auto run_strategy = [&](const char* name, int id,
        std::function<BenchResult(const std::vector<BlockHeader>&, BlockMap&, std::mutex&)> fn)
    {
        BlockMap idx;
        std::mutex cs;
        int64_t total_us = 0, total_cont = 0, total_accept = 0;
        size_t  total_new = 0, total_dup = 0;

        for (auto& b : batches) {
            auto r = fn(b, idx, cs);
            total_us     += r.total_us;
            total_cont   += r.continuity_us;
            total_accept += r.accept_us;
            total_new    += r.new_headers;
            total_dup    += r.dup_headers;
        }

        double sec = total_us / 1e6;
        double hps = total_new / sec;
        printf("  Strategy %d: %-32s\n", id, name);
        printf("    Total      : %8.2f s  (%7.0f hdr/s)\n", sec, hps);
        printf("    Phase1     : %8.2f s  (hash/continuity)\n", total_cont / 1e6);
        printf("    Phase2     : %8.2f s  (accept/index)\n", total_accept / 1e6);
        printf("    New/Dup    : %zu / %zu\n", total_new, total_dup);
        printf("    Per header : %6.0f μs\n", (double)total_us / total_new);
        printf("\n");
        return sec;
    };

    printf("───────────────────────────────────────────────────────────────────\n");
    printf("  Running benchmarks...\n");
    printf("───────────────────────────────────────────────────────────────────\n\n");

    double t_baseline = run_strategy("Baseline (4× RinHash, serial)", 0,
        [](auto& b, auto& idx, auto& cs) { return strategy0_baseline(b, idx, cs); });

    double t_cache = run_strategy("Hash-cache (1× RinHash, serial)", 1,
        [](auto& b, auto& idx, auto& cs) { return strategy1_hash_cache(b, idx, cs); });

    ThreadPool pool2(pool_size);
    double t_parallel = run_strategy("Parallel PoW (4× RinHash, N threads)", 2,
        [&](auto& b, auto& idx, auto& cs) { return strategy2_parallel_pow(b, idx, cs, pool2); });
    pool2.shutdown();

    ThreadPool pool3(pool_size);
    double t_combined = run_strategy("Parallel + cache (1× RinHash, N threads)", 3,
        [&](auto& b, auto& idx, auto& cs) { return strategy3_parallel_cache(b, idx, cs, pool3); });
    pool3.shutdown();

    /* --- Summary --- */
    printf("═══════════════════════════════════════════════════════════════════\n");
    printf("  SPEEDUP SUMMARY  (vs baseline)\n");
    printf("═══════════════════════════════════════════════════════════════════\n");
    printf("  Strategy 0 (baseline)          : 1.00×  (%.2f s)\n", t_baseline);
    printf("  Strategy 1 (hash-cache)        : %.2f×  (%.2f s)\n", t_baseline / t_cache, t_cache);
    printf("  Strategy 2 (parallel PoW)      : %.2f×  (%.2f s)\n", t_baseline / t_parallel, t_parallel);
    printf("  Strategy 3 (parallel + cache)  : %.2f×  (%.2f s)\n", t_baseline / t_combined, t_combined);
    printf("═══════════════════════════════════════════════════════════════════\n");

    /* Cleanup: free BlockIndex allocations */
    /* (Not critical for a benchmark tool, OS reclaims on exit) */

    return 0;
}
