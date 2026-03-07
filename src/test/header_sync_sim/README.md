# Header Sync Simulator

Standalone test app that simulates the Rincoin block-header initial-sync
pipeline **without** a full node, P2P layer, or disk database.

## Purpose

Measure and compare different header-processing strategies:

1. **Baseline** — current code: 4× RinHash per new header, single-threaded,
   cs_main held for entire 2000-header batch.
2. **Hash-caching** — compute RinHash once per header, pass the result down to
   avoid redundant calls.
3. **Parallel PoW** — validate PoW hashes in a worker-thread pool *before*
   taking cs_main, then do only the index insertion under lock.
4. **Batched parallel PoW + cache** — combines both strategies.

## Build

```bash
cd /home/tomas_admin/rincoin
make -C src/test/header_sync_sim -j$(nproc)
```

## Run

```bash
./src/test/header_sync_sim/header_sync_sim [num_headers] [batch_size]
```

Defaults: 20000 headers, batch size 2000 (matching MAX_HEADERS_RESULTS).
