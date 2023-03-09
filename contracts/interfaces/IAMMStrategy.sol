// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IStrategy.sol";

/// @title IAMMStrategy Interface
/// @author imToken Labs
interface IAMMStrategy is IStrategy {
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

    /// @notice Only owner can call
    /// @param _ammAddrs The amm addresses allowed to use in `executeStrategy` if according `enable` equals `true`
    /// @param _enables The status of accouring amm addresses
    function setAMMs(address[] calldata _ammAddrs, bool[] calldata _enables) external;

    /// @notice Only owner can call
    /// @param _assetAddrs The asset addresses
    /// @param _ammAddrs The approved amm addresses
    /// @param _assetAmount The approved asset amount
    function approveAssets(
        address[] calldata _assetAddrs,
        address[] calldata _ammAddrs,
        uint256 _assetAmount
    ) external;
}
