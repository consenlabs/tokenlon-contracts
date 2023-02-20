// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
pragma abicoder v2;

import "./IStrategy.sol";

/// @title IAMMStrategy Interface
/// @author imToken Labs
interface IAMMStrategy is IStrategy {
    /// @notice Emitted when entry point address is updated
    /// @param newEntryPoint The address of the new entry point
    event SetEntryPoint(address newEntryPoint);

    /// @notice Emitted when allowed amm is updated
    /// @param ammAddr The address of the amm
    /// @param enable The status of amm
    event SetAMM(address ammAddr, bool enable);

    /// @notice Emitted after swap with AMM
    /// @param takerAssetAddr The taker assest used to swap
    /// @param takerAssetAmount The swap amount of taker asset
    /// @param makerAddr The address of maker
    /// @param makerAssetAddr The maker assest used to swap
    /// @param makerAssetAmount The swap amount of maker asset
    event Swapped(address takerAssetAddr, uint256 takerAssetAmount, address[] makerAddr, address makerAssetAddr, uint256 makerAssetAmount);

    /** @dev The encoded operation list should be passed as `data` when calling `IStrategy.executeStrategy` */
    struct Operation {
        address dest;
        bytes data;
    }
}
