### This script is a helper that generates preview of Base58 addresses with specific prefixes for Rincoin. You can use it for checking the prefixes.

import base58
import hashlib
import os

# Hardcoded Base58 prefixes (change as needed)
prefixes = {
    "mainnet_pubkey": 0x3C,   
    "mainnet_script": 0x7A,   
    "mainnet_seckey": 188,   
    "testnet_pubkey": 0x41,   
    "testnet_script": 0x7F,   
    "testnet_seckey": 218,   
    "mainnet_ext_seckey": (0x04, 0x88, 0xAD, 0xE4),
    "mainnet_ext_pubkey": (0x04, 0x88, 0xB2, 0x1E),
    "testnet_ext_pubkey": (0x04, 0x35, 0x87, 0xCF),
    "testnet_ext_privkey": (0x04, 0x35, 0x83, 0x94),
}

def base58_address(prefix, payload):
    if isinstance(prefix, int):
        data = bytes([prefix]) + payload
    elif isinstance(prefix, tuple) or isinstance(prefix, list):
        data = bytes(prefix) + payload
    else:
        raise ValueError("Prefix must be int or tuple/list of ints")
    checksum = hashlib.sha256(hashlib.sha256(data).digest()).digest()[:4]
    return base58.b58encode(data + checksum).decode()

for name, prefix in prefixes.items():
    # Determine payload length: 20 bytes for addresses, 32 for secret keys, 33 for ext keys
    if 'ext' in name:
            payload_len = 74  # 74 bytes for extended keys (BIP32: 78 total incl. 4 prefix)
    elif 'seckey' in name:
        payload_len = 32  # 32 bytes for WIF private keys
    else:
        payload_len = 20  # 20 bytes for addresses

    prefix_str = (
        '0x' + ''.join(f'{b:02X}' for b in prefix)
        if isinstance(prefix, (tuple, list))
        else hex(prefix)
    )
    print(f"\n{name} (prefix {prefix_str}):")
    for i in range(20):
        payload = os.urandom(payload_len)
        addr = base58_address(prefix, payload)
        print(addr)