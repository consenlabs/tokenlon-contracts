// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IStrategy } from "./IStrategy.sol";

/// @title IAMMStrategy Interface
/// @author imToken Labs
interface IAMMStrategy is IStrategy {
    /// @notice Emitted when allowed amm is updated
    /// @param ammAddr The address of the amm
    /// @param enable The status of amm
    event SetAMM(address ammAddr, bool enable);

    /// @notice Emitted after swap with AMM
    /// @param inputToken The taker assest used to swap
    /// @param inputAmount The swap amount of taker asset
    /// @param outputToken The maker assest used to swap
    /// @param outputAmount The swap amount of maker asset
    event Swapped(address inputToken, uint256 inputAmount, address outputToken, uint256 outputAmount);

    /** @dev The encoded operation list should be passed as `data` when calling `IStrategy.executeStrategy` */
    struct Operation {
        address dest;
        uint256 value;
        bytes data;
    }

    /// @notice Only owner can call
    /// @param _ammAddrs The amm addresses allowed to use in `executeStrategy` if according `enable` equals `true`
    /// @param _enables The status of accouring amm addresses
    function setAMMs(address[] calldata _ammAddrs, bool[] calldata _enables) external;

    /// @notice Only owner can call
    /// @param tokens The address list of assets
    /// @param spenders The address list of approved amms
    /// @param amount The approved asset amount
    function approveTokens(
        address[] calldata tokens,
        address[] calldata spenders,
        uint256 amount
    ) external;
}
