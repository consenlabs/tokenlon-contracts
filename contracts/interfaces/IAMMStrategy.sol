// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
pragma abicoder v2;

import "./IStrategy.sol";

/// @title IAMMStrategy Interface
/// @author imToken Labs
interface IAMMStrategy is IStrategy {
    /// @notice Emitted when address of generic swap is updated
    /// @param newGenericSwap The address of the new generic swap
    event SetGenericSwap(address newGenericSwap);

    /// @notice Emitted after swap with AMM
    /// @param inputToken The taker assest used to swap
    /// @param inputAmount The swap amount of taker asset
    /// @param routerAddrList The addresses of all makers
    /// @param outputToken The maker assest used to swap
    /// @param outputAmount The swap amount of maker asset
    event Swapped(address inputToken, uint256 inputAmount, address[] routerAddrList, address outputToken, uint256 outputAmount);

    /// @notice Only owner can call
    /// @param newGenericSwap The address allowed to call `executeStrategy`
    function setGenericSwap(address newGenericSwap) external;

    /// @notice Only owner can call
    /// @param tokenList The address list of assets
    /// @param spenderList The address list of approved amms
    /// @param amount The approved asset amount
    function approveTokenList(
        address[] calldata tokenList,
        address[] calldata spenderList,
        uint256 amount
    ) external;
}
