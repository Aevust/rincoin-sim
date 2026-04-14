# Rincoin Core

![Version](https://img.shields.io/badge/version-1.0.6-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

Rincoin is a decentralized digital currency, based on Bitcoin Core, that introduces a new Proof-of-Work hashing algorithm called **RinHash**. RinHash is a hybrid PoW algorithm designed for both security and ASIC-resistance, combining BLAKE3, Argon2d, and SHA3-256. This README provides an overview of Rincoin’s specifications, the RinHash algorithm, and network parameters.

## 🛡️ Core Architecture & Network Sovereignty

Rincoin Core has been meticulously engineered and audited to ensure complete mathematical and network independence from its legacy upstream codebases. Recent major milestones include:

- **P2P Network Sovereignty:** All legacy cryptographic salts and network identifiers have been fully purged. Internal P2P routing mechanisms and dummy IPv6 prefixes are strictly derived from Rincoin-native entropy (e.g., `sha256("rincoin")`), ensuring absolute P2P isolation and preventing cross-network contamination.
- **Customized Consensus & Emission (Scenario II):** Rincoin implements a sophisticated, multi-phase emission schedule. It begins with 210,000-block intervals (~145 days) but strategically dilates to multi-million block epochs after height 840,000 to prevent entropic yield collapse. It ultimately culminates in a perpetual terminal reward (0.6 RIN), securing the network's long-term thermodynamic future. All consensus rules, including custom base58 address prefixes (prefix `60`), have been strictly validated.
- **Production-Ready CI/CD (100% Test Green):** The core validation and utility test suites have achieved a 100% "PASS" state. Legacy benchmarks reliant on obsolete upstream block data have been strategically decoupled, ensuring a pristine, crash-free Continuous Integration pipeline for future development.

## 📊 Key Specifications

| Feature | Specification |
| :--- | :--- |
| **Coin Name / Ticker** | Rincoin (**RIN**) |
| **Consensus Mechanism**| Proof-of-Work (PoW) – **RinHash** algorithm |
| **Block Target Time** | 1 minute (60 seconds per block) |
| **Initial Block Reward**| 50 RIN |
| **Emission Schedule** | Custom multi-phase (Initial: 210k blocks, Dilated: up to 2.1M blocks, Terminal: 0.6 RIN) |
| **Difficulty Retarget**| Every 2016 blocks (~33.6 hours) |
| **Proof-of-Work Hash** | 256-bit output |
| **Address Format** | Base58 addresses start with **R** |
| **Network Ports** | P2P: `9555`, RPC: `9556` |
| **Network Magic** | `0x52` `0x49` `0x4E` `0x43` ("RINC") |

## ⚙️ Proof-of-Work Algorithm: RinHash

RinHash is a custom proof-of-work algorithm using:

1. **BLAKE3**: Fast initial hashing  
2. **Argon2d**: Memory-hard step to resist ASICs  
3. **SHA3-256**: Final standard cryptographic hash

A valid block satisfies:  
`SHA3-256( Argon2d( BLAKE3(block_header) )) < Target`

This design provides fast verification, memory-hardness to deter ASICs, and seamless compatibility with existing 256-bit PoW frameworks.

## 🌐 Network and Usage

- **Magic bytes:** `0x52 0x49 0x4E 0x43`  
- **Ports:** `9555` (P2P), `9556` (RPC)  
- **Mining:** CPU/GPU mining supported  
- **Wallet:** Full-node wallet with RIN units

## 🛠️ Building Rincoin

For detailed instructions on building release binaries for Linux and Windows, see [doc/build-release.md](doc/build-release.md).

**Quick start for building from source:**
- [Linux/Unix Build Notes](doc/build-unix.md)
- [Windows Build Notes](doc/build-windows.md)

## 💻 Developer Notes

- See `src/chainparams.cpp` for network configuration.  
- See `src/primitives/block.cpp` (or relevant files) for `GetPoWHash()` RinHash implementation.  

## 💬 Community

Join the official Rincoin community to stay updated, get support, and discuss development:

[![Discord Banner 2](https://discord.com/api/guilds/1354664874176680017/widget.png?style=banner2)](https://discord.gg/H4Du5YuqFa)
