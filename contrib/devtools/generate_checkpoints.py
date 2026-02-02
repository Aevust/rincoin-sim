#!/usr/bin/env python3
"""
Generate checkpoint data for chainparams.cpp

This script connects to a rincoin RPC node and generates checkpoint data
by fetching block hashes at specified intervals.
"""

import argparse
import json
import random
import sys
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from base64 import b64encode


class RinCoinRPC:
    """Simple RPC client for RinCoin daemon"""
    
    def __init__(self, host, port, user=None, password=None, cookie_path=None):
        self.url = f"http://{host}:{port}"
        self.user = user
        self.password = password
        
        if cookie_path:
            try:
                with open(cookie_path, 'r') as f:
                    cookie_data = f.read().strip()
                    self.user, self.password = cookie_data.split(':')
            except Exception as e:
                print(f"Error reading cookie file: {e}", file=sys.stderr)
                sys.exit(1)
        
        if not self.user or not self.password:
            print("Error: RPC authentication not properly configured", file=sys.stderr)
            sys.exit(1)
    
    def call(self, method, params=None):
        """Make an RPC call"""
        if params is None:
            params = []
        
        payload = json.dumps({
            "jsonrpc": "1.0",
            "id": "checkpoint_generator",
            "method": method,
            "params": params
        }).encode('utf-8')
        
        auth = b64encode(f"{self.user}:{self.password}".encode('utf-8')).decode('ascii')
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Basic {auth}'
        }
        
        try:
            request = Request(self.url, data=payload, headers=headers)
            with urlopen(request, timeout=30) as response:
                result = json.loads(response.read().decode('utf-8'))
                
                if result.get('error'):
                    print(f"RPC Error: {result['error']}", file=sys.stderr)
                    return None
                
                return result.get('result')
        except HTTPError as e:
            print(f"HTTP Error {e.code}: {e.reason}", file=sys.stderr)
            return None
        except URLError as e:
            print(f"URL Error: {e.reason}", file=sys.stderr)
            return None
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            return None


def get_block_count(rpc):
    """Get the current block count"""
    return rpc.call("getblockcount")


def get_block_hash(rpc, height):
    """Get the block hash at a given height"""
    return rpc.call("getblockhash", [height])


def generate_checkpoints(rpc, step, use_random, start_from=0):
    """Generate checkpoint data"""
    block_count = get_block_count(rpc)
    
    if block_count is None:
        print("Error: Could not get block count from RPC", file=sys.stderr)
        sys.exit(1)
    
    print(f"Current blockchain height: {block_count}", file=sys.stderr)
    print(f"Starting from block: {start_from}", file=sys.stderr)
    
    checkpoints = []
    current_height = start_from
    
    while current_height <= block_count:
        block_hash = get_block_hash(rpc, current_height)
        
        if block_hash is None:
            print(f"Warning: Could not get hash for block {current_height}", file=sys.stderr)
            current_height += step
            continue
        
        checkpoints.append((current_height, block_hash))
        print(f"Added checkpoint: block {current_height}: {block_hash}", file=sys.stderr)
        
        # Calculate next step
        if use_random and step > 0:
            # Random between 0.5*step and 1.5*step
            min_step = max(1, int(step * 0.5))
            max_step = int(step * 1.5)
            next_step = random.randint(min_step, max_step)
        else:
            next_step = step
        
        current_height += next_step
        
        # Ensure we don't skip past the last block
        if current_height > block_count and checkpoints[-1][0] != block_count:
            current_height = block_count
    
    return checkpoints


def format_checkpoints(checkpoints):
    """Format checkpoints for chainparams.cpp"""
    lines = ["        checkpointData = {", "            {"]
    
    for height, block_hash in checkpoints:
        lines.append(f"                {{{height}, uint256S(\"0x{block_hash}\")}},")
    
    lines.append("            }")
    lines.append("        };")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Generate checkpoint data for rincoin chainparams.cpp',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Using cookie authentication
  %(prog)s --rpchost localhost:9555 --rpccookie ~/.rincoin/.cookie --step 10000
  
  # Using username/password
  %(prog)s --rpchost localhost:9555 --rpcuser user --rpcpassword pass --step 10000
  
  # With random intervals
  %(prog)s --rpchost localhost:9555 --rpccookie ~/.rincoin/.cookie --step 10000 --random yes
  
  # Starting from a specific block
  %(prog)s --rpchost localhost:9555 --rpccookie ~/.rincoin/.cookie --step 10000 --from 100000
        """
    )
    
    parser.add_argument('--rpchost', required=True,
                        help='RPC host in format host:port (e.g., localhost:9555)')
    parser.add_argument('--rpccookie',
                        help='Path to .cookie file for authentication')
    parser.add_argument('--rpcuser',
                        help='RPC username (alternative to cookie)')
    parser.add_argument('--rpcpassword',
                        help='RPC password (alternative to cookie)')
    parser.add_argument('--step', type=int, required=True,
                        help='Block height increment')
    parser.add_argument('--from', type=int, default=0, dest='start_from',
                        help='Starting block height (default: 0)')
    parser.add_argument('--random', choices=['yes', 'no'], default='no',
                        help='Randomize step between 0.5*step and 1.5*step')
    
    args = parser.parse_args()
    
    # Validate authentication
    if not args.rpccookie and not (args.rpcuser and args.rpcpassword):
        parser.error('Either --rpccookie or both --rpcuser and --rpcpassword are required')
    
    if args.rpccookie and (args.rpcuser or args.rpcpassword):
        parser.error('Cannot use both cookie and username/password authentication')
    
    # Parse host and port
    try:
        host, port = args.rpchost.rsplit(':', 1)
        port = int(port)
    except ValueError:
        parser.error('Invalid --rpchost format. Use host:port (e.g., localhost:9555)')
    
    # Validate step
    if args.step < 1:
        parser.error('--step must be at least 1')
    
    # Create RPC client
    rpc = RinCoinRPC(
        host=host,
        port=port,
        user=args.rpcuser,
        password=args.rpcpassword,
        cookie_path=args.rpccookie
    )
    
    # Test connection
    block_count = get_block_count(rpc)
    if block_count is None:
        print("Error: Could not connect to RPC server", file=sys.stderr)
        sys.exit(1)
    
    # Validate start_from
    if args.start_from < 0:
        parser.error('--from must be 0 or greater')
    
    # Generate checkpoints
    use_random = (args.random == 'yes')
    checkpoints = generate_checkpoints(rpc, args.step, use_random, args.start_from)
    
    if not checkpoints:
        print("Error: No checkpoints generated", file=sys.stderr)
        sys.exit(1)
    
    # Format and output
    output = format_checkpoints(checkpoints)
    print("\n" + "="*70, file=sys.stderr)
    print("Generated checkpoint data:", file=sys.stderr)
    print("="*70 + "\n", file=sys.stderr)
    print(output)
    print("\n" + "="*70, file=sys.stderr)
    print(f"Total checkpoints: {len(checkpoints)}", file=sys.stderr)
    print("="*70, file=sys.stderr)


if __name__ == "__main__":
    main()
