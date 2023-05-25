// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IStrategy } from "./IStrategy.sol";

/// @title ISmartOrderStrategy Interface
/// @author imToken Labs
interface ISmartOrderStrategy is IStrategy {
    error ZeroInput();
    error EmptyOps();
    error InvalidMsgValue();
    error NotFromGS();

    /// @notice Event emitted for each executed operation.
    /// @param dest The target address of the operation
    /// @param value The eth value carried when calling `dest`
    /// @param selector The selector when calling `dest`
    event Action(address indexed dest, uint256 value, bytes4 selector);

    /// @dev The encoded operation list should be passed as `data` when calling `IStrategy.executeStrategy`
    struct Operation {
        address dest;
        address inputToken;
        uint128 inputRatio;
        uint128 dataOffset;
        uint256 value;
        bytes data;
    }

    /// @notice Only owner can call
    /// @param tokens The address list of tokens
    /// @param spenders The address list of spenders
    function approveTokens(address[] calldata tokens, address[] calldata spenders) external;

    /// @notice Only owner can call
    /// There may be some tokens left after swap while the order has been filled
    /// @param tokens The address list of tokens
    /// @param recipient The recipient address
    function withdrawTokens(address[] calldata tokens, address recipient) external;
}
