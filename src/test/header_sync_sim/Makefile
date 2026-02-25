# Makefile for the Rincoin Header-Sync Simulator

RINCOIN      := $(realpath ../../..)
SRC          := $(RINCOIN)/src
CRYPTO       := $(SRC)/crypto
BLAKE3_DIR   := $(CRYPTO)/blake3
ARGON2_DIR   := $(CRYPTO)/argon2

CXX          := g++
CC           := gcc
CXXFLAGS     := -std=c++17 -O2 -Wall -Wextra -pthread
CFLAGS       := -std=c11 -O3 -Wall -fPIC

INCLUDES     := -I$(BLAKE3_DIR) -I$(ARGON2_DIR)/include -I.

OBJS := build/header_sync_sim.o \
	build/blake3.o \
	build/blake3_dispatch.o \
	build/blake3_portable.o \
	build/blake3_sse2.o \
	build/blake3_sse41.o \
	build/blake3_avx2.o \
	build/blake3_avx512.o \
	build/argon2.o \
	build/argon2_core.o \
	build/argon2_ref.o \
	build/argon2_thread.o \
	build/argon2_encoding.o \
	build/argon2_blake2b.o \
	build/argon2_dispatch.o \
	build/argon2_ssse3.o \
	build/argon2_avx2.o \
	build/argon2_avx512.o

TARGET := header_sync_sim

all: builddir $(TARGET)

builddir:
	@mkdir -p build

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ -lpthread

build/header_sync_sim.o: header_sync_sim.cpp sha3_standalone.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

build/blake3.o: $(BLAKE3_DIR)/blake3.c
	$(CC) $(CFLAGS) -I$(BLAKE3_DIR) -c $< -o $@

build/blake3_dispatch.o: $(BLAKE3_DIR)/blake3_dispatch.c
	$(CC) $(CFLAGS) -I$(BLAKE3_DIR) -c $< -o $@

build/blake3_portable.o: $(BLAKE3_DIR)/blake3_portable.c
	$(CC) $(CFLAGS) -I$(BLAKE3_DIR) -c $< -o $@

build/blake3_sse2.o: $(BLAKE3_DIR)/blake3_sse2_x86-64_unix.S
	$(CC) -c $< -o $@

build/blake3_sse41.o: $(BLAKE3_DIR)/blake3_sse41_x86-64_unix.S
	$(CC) -c $< -o $@

build/blake3_avx2.o: $(BLAKE3_DIR)/blake3_avx2_x86-64_unix.S
	$(CC) -c $< -o $@

build/blake3_avx512.o: $(BLAKE3_DIR)/blake3_avx512_x86-64_unix.S
	$(CC) -c $< -o $@

ARGON2_CFLAGS := $(CFLAGS) -I$(ARGON2_DIR)/include -I$(ARGON2_DIR)

build/argon2.o: $(ARGON2_DIR)/argon2.c
	$(CC) $(ARGON2_CFLAGS) -c $< -o $@

build/argon2_core.o: $(ARGON2_DIR)/core.c
	$(CC) $(ARGON2_CFLAGS) -c $< -o $@

build/argon2_ref.o: $(ARGON2_DIR)/ref.c
	$(CC) $(ARGON2_CFLAGS) -c $< -o $@

build/argon2_thread.o: $(ARGON2_DIR)/thread.c
	$(CC) $(ARGON2_CFLAGS) -c $< -o $@

build/argon2_encoding.o: $(ARGON2_DIR)/encoding.c
	$(CC) $(ARGON2_CFLAGS) -c $< -o $@

build/argon2_blake2b.o: $(ARGON2_DIR)/blake2/blake2b.c
	$(CC) $(ARGON2_CFLAGS) -I$(ARGON2_DIR)/blake2 -c $< -o $@

build/argon2_dispatch.o: $(ARGON2_DIR)/argon2_dispatch.c
	$(CC) $(ARGON2_CFLAGS) -c $< -o $@

build/argon2_ssse3.o: $(ARGON2_DIR)/argon2_ssse3.c
	$(CC) $(ARGON2_CFLAGS) -mssse3 -c $< -o $@

build/argon2_avx2.o: $(ARGON2_DIR)/argon2_avx2.c
	$(CC) $(ARGON2_CFLAGS) -mavx2 -c $< -o $@

build/argon2_avx512.o: $(ARGON2_DIR)/argon2_avx512.c
	$(CC) $(ARGON2_CFLAGS) -mavx512f -c $< -o $@

clean:
	rm -rf build $(TARGET)

.PHONY: all clean builddir
