/*
 * Minimal standalone SHA3-256 for the header sync simulator.
 *
 * Based on the tiny_sha3 reference by Markku-Juhani O. Saarinen.
 * Public domain / MIT.
 */
#ifndef SHA3_STANDALONE_H
#define SHA3_STANDALONE_H

#include <cstdint>
#include <cstddef>
#include <cstring>

namespace {

static inline uint64_t sha3_rotl64(uint64_t x, int n) {
    return (x << n) | (x >> (64 - n));
}

static void keccakf(uint64_t st[25]) {
    static const uint64_t RC[24] = {
        0x0000000000000001ULL, 0x0000000000008082ULL,
        0x800000000000808aULL, 0x8000000080008000ULL,
        0x000000000000808bULL, 0x0000000080000001ULL,
        0x8000000080008081ULL, 0x8000000000008009ULL,
        0x000000000000008aULL, 0x0000000000000088ULL,
        0x0000000080008009ULL, 0x000000008000000aULL,
        0x000000008000808bULL, 0x800000000000008bULL,
        0x8000000000008089ULL, 0x8000000000008003ULL,
        0x8000000000008002ULL, 0x8000000000000080ULL,
        0x000000000000800aULL, 0x800000008000000aULL,
        0x8000000080008081ULL, 0x8000000000008080ULL,
        0x0000000080000001ULL, 0x8000000080008008ULL
    };
    static const int ROTC[24] = {
        1,3,6,10,15,21,28,36,45,55,2,14,27,41,56,8,25,43,62,18,39,61,20,44
    };
    static const int PILN[24] = {
        10,7,11,17,18,3,5,16,8,21,24,4,15,23,19,13,12,2,20,14,22,9,6,1
    };

    for (int r = 0; r < 24; ++r) {
        /* Theta */
        uint64_t bc[5];
        for (int i = 0; i < 5; ++i)
            bc[i] = st[i] ^ st[i+5] ^ st[i+10] ^ st[i+15] ^ st[i+20];
        for (int i = 0; i < 5; ++i) {
            uint64_t t = bc[(i+4)%5] ^ sha3_rotl64(bc[(i+1)%5], 1);
            for (int j = 0; j < 25; j += 5) st[j+i] ^= t;
        }
        /* Rho Pi */
        uint64_t t = st[1];
        for (int i = 0; i < 24; ++i) {
            int j = PILN[i];
            uint64_t tmp = st[j];
            st[j] = sha3_rotl64(t, ROTC[i]);
            t = tmp;
        }
        /* Chi */
        for (int j = 0; j < 25; j += 5) {
            uint64_t b0 = st[j], b1 = st[j+1], b2 = st[j+2], b3 = st[j+3], b4 = st[j+4];
            st[j]   = b0 ^ (~b1 & b2);
            st[j+1] = b1 ^ (~b2 & b3);
            st[j+2] = b2 ^ (~b3 & b4);
            st[j+3] = b3 ^ (~b4 & b0);
            st[j+4] = b4 ^ (~b0 & b1);
        }
        /* Iota */
        st[0] ^= RC[r];
    }
}

} /* anonymous namespace */

/*
 * SHA3-256: absorb `inlen` bytes from `in`, write 32 bytes to `out`.
 */
static void sha3_256(const uint8_t* in, size_t inlen, uint8_t* out) {
    constexpr size_t RATE = 136;           /* (1600 - 2*256) / 8 */
    uint64_t st[25];
    std::memset(st, 0, sizeof(st));

    /* Absorb */
    uint8_t* sb = reinterpret_cast<uint8_t*>(st);
    while (inlen >= RATE) {
        for (size_t i = 0; i < RATE; ++i) sb[i] ^= in[i];
        keccakf(st);
        in += RATE;
        inlen -= RATE;
    }
    /* Last block + padding */
    for (size_t i = 0; i < inlen; ++i) sb[i] ^= in[i];
    sb[inlen] ^= 0x06;     /* SHA3 domain separator */
    sb[RATE-1] ^= 0x80;
    keccakf(st);

    /* Squeeze 32 bytes */
    std::memcpy(out, st, 32);
}

#endif /* SHA3_STANDALONE_H */
