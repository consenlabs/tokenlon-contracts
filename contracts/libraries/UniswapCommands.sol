// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Commands
/// @notice Command Flags used to decode commands
library Commands {
    // Masks to extract certain bits of commands
    bytes1 internal constant FLAG_ALLOW_REVERT = 0x80;
    bytes1 internal constant COMMAND_TYPE_MASK = 0x3f;

    // Command Types. Maximum supported command at this moment is 0x3f.

    // Command Types where value<0x08, executed in the first nested-if block
    uint256 internal constant V3_SWAP_EXACT_IN = 0x00;
    uint256 internal constant V3_SWAP_EXACT_OUT = 0x01;
    uint256 internal constant PERMIT2_TRANSFER_FROM = 0x02;
    uint256 internal constant PERMIT2_PERMIT_BATCH = 0x03;
    uint256 internal constant SWEEP = 0x04;
    uint256 internal constant TRANSFER = 0x05;
    uint256 internal constant PAY_PORTION = 0x06;
    // COMMAND_PLACEHOLDER = 0x07;

    // Command Types where 0x08<=value<=0x0f, executed in the second nested-if block
    uint256 internal constant V2_SWAP_EXACT_IN = 0x08;
    uint256 internal constant V2_SWAP_EXACT_OUT = 0x09;
    uint256 internal constant PERMIT2_PERMIT = 0x0a;
    uint256 internal constant WRAP_ETH = 0x0b;
    uint256 internal constant UNWRAP_WETH = 0x0c;
    uint256 internal constant PERMIT2_TRANSFER_FROM_BATCH = 0x0d;
    uint256 internal constant BALANCE_CHECK_ERC20 = 0x0e;
    // COMMAND_PLACEHOLDER = 0x0f;

    // Command Types where 0x10<=value<0x18, executed in the third nested-if block
    uint256 internal constant SEAPORT = 0x10;
    uint256 internal constant LOOKS_RARE_721 = 0x11;
    uint256 internal constant NFTX = 0x12;
    uint256 internal constant CRYPTOPUNKS = 0x13;
    uint256 internal constant LOOKS_RARE_1155 = 0x14;
    uint256 internal constant OWNER_CHECK_721 = 0x15;
    uint256 internal constant OWNER_CHECK_1155 = 0x16;
    uint256 internal constant SWEEP_ERC721 = 0x17;

    // Command Types where 0x18<=value<=0x1f, executed in the final nested-if block
    uint256 internal constant X2Y2_721 = 0x18;
    uint256 internal constant SUDOSWAP = 0x19;
    uint256 internal constant NFT20 = 0x1a;
    uint256 internal constant X2Y2_1155 = 0x1b;
    uint256 internal constant FOUNDATION = 0x1c;
    uint256 internal constant SWEEP_ERC1155 = 0x1d;
    uint256 internal constant ELEMENT_MARKET = 0x1e;
    // COMMAND_PLACEHOLDER = 0x1f;

    // Command Types where 0x20<=value
    uint256 internal constant EXECUTE_SUB_PLAN = 0x20;
    uint256 internal constant SEAPORT_V2 = 0x21;
    // COMMAND_PLACEHOLDER for 0x22 to 0x3f (all unused)
}
