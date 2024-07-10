// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IStrategy } from "./IStrategy.sol";

/// @title ISmartOrderStrategy Interface
/// @author imToken Labs
interface ISmartOrderStrategy is IStrategy {
    /// @notice Error thrown when the input is zero.
    /// @dev Thrown when an operation requires a non-zero input value that is not provided.
    error ZeroInput();

    /// @notice Error thrown when the denominator is zero.
    /// @dev Thrown when an operation requires a non-zero denominator that is not provided.
    error ZeroDenominator();

    /// @notice Error thrown when the operation list is empty.
    /// @dev Thrown when an operation list is required to be non-empty but is empty.
    error EmptyOps();

    /// @notice Error thrown when the msg.value is invalid.
    /// @dev Thrown when an operation requires a specific msg.value that is not provided.
    error InvalidMsgValue();

    /// @notice Error thrown when the input ratio is invalid.
    /// @dev Thrown when an operation requires a valid input ratio that is not provided or is invalid.
    error InvalidInputRatio();

    /// @notice Error thrown when the operation is not from a Governance System (GS).
    /// @dev Thrown when an operation is attempted by an unauthorized caller that is not from a Governance System (GS).
    error NotFromGS();

    /// @title Operation
    /// @notice Struct containing parameters for the operation.
    /// @dev The encoded operation list should be passed as `data` when calling `IStrategy.executeStrategy`
    struct Operation {
        address dest;
        address inputToken;
        uint256 ratioNumerator;
        uint256 ratioDenominator;
        uint256 dataOffset;
        uint256 value;
        bytes data;
    }
}
