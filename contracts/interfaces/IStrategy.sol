// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IStrategy Interface
/// @author imToken Labs
/// @notice Interface for a strategy contract that executes a specific trading strategy.
interface IStrategy {
    /// @notice Executes the strategy to trade `inputAmount` of `inputToken` for `outputToken`.
    /// @dev Implementations should handle the logic to trade tokens based on the provided parameters.
    /// @param inputToken The token to be traded from.
    /// @param outputToken The token to be received after the trade.
    /// @param inputAmount The amount of `inputToken` to be traded.
    /// @param data Additional data needed for executing the strategy, encoded as bytes.
    function executeStrategy(address inputToken, address outputToken, uint256 inputAmount, bytes calldata data) external payable;
}
