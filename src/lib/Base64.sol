// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*───────────────────────────────────────────────────────────────────────────
  Base64 — the only way a contract can hand a browser a whole document

  A data: URI is the entire distribution channel for an on-chain artwork.
  This runs on the return path of every tokenURI() call, over a payload
  measured in tens of kilobytes, so it is written as one assembly loop
  that reads three bytes and writes four with no bounds checks and no
  memory expansion beyond the single allocation.
───────────────────────────────────────────────────────────────────────────*/
library Base64 {
    bytes internal constant TABLE =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function encode(bytes memory data) internal pure returns (string memory result) {
        if (data.length == 0) return "";

        // 4 characters out for every 3 bytes in, rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // +32 slack so the final 3-byte read can never run off the allocation
        result = new string(encodedLen + 32);

        // constants of reference type cannot be addressed from assembly; copy
        // the alphabet into memory once and index it there
        bytes memory alphabet = TABLE;

        assembly ("memory-safe") {
            let table := add(alphabet, 1)
            let out := add(result, 32)
            let input := data
            let end := add(data, mload(data))

            for {} lt(input, end) {} {
                input := add(input, 3)
                let chunk := mload(input)          // 3 payload bytes in the low 24 bits

                let o := mload(add(table, and(shr(18, chunk), 0x3F)))
                o := shl(8, o)
                o := add(o, and(mload(add(table, and(shr(12, chunk), 0x3F))), 0xFF))
                o := shl(8, o)
                o := add(o, and(mload(add(table, and(shr(6, chunk), 0x3F))), 0xFF))
                o := shl(8, o)
                o := add(o, and(mload(add(table, and(chunk, 0x3F))), 0xFF))

                mstore8(out, shr(24, o)) out := add(out, 1)
                mstore8(out, shr(16, o)) out := add(out, 1)
                mstore8(out, shr(8, o))  out := add(out, 1)
                mstore8(out, o)          out := add(out, 1)
            }

            // pad the tail
            switch mod(mload(data), 3)
            case 1 { mstore8(sub(out, 1), 0x3d) mstore8(sub(out, 2), 0x3d) }
            case 2 { mstore8(sub(out, 1), 0x3d) }

            mstore(result, encodedLen)
        }
    }
}
