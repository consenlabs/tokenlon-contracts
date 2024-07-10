// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Constant Library
/// @author imToken Labs
/// @notice Library for defining constant values used across contracts
library Constant {
    /// @dev Maximum value for basis points (BPS)
    uint16 internal constant BPS_MAX = 10000;
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant ZERO_ADDRESS = address(0);
}
