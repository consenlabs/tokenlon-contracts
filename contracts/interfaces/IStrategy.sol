// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IStrategy Interface
/// @author imToken Labs
/// @notice Interface for contract that implements a specific trading strategy.
interface IStrategy {
    /// @notice Executes the trading strategy for the target token.
    /// @dev Implementations should handle the logic to trade tokens based on the provided parameters.
    /// @param targetToken The token to be received after executing the strategy.
    /// @param strategyData Encoded calldata that combines a sequence of instructions for trading the target token.
    function executeStrategy(address targetToken, bytes calldata strategyData) external payable;
}
