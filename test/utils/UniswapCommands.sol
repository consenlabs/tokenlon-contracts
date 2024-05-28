// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library UniswapCommands {
    bytes1 internal constant FLAG_ALLOW_REVERT = 0x80;
    bytes1 internal constant COMMAND_TYPE_MASK = 0x3f;

    uint256 internal constant V3_SWAP_EXACT_IN = 0x00;
    uint256 internal constant V2_SWAP_EXACT_IN = 0x08;
}
