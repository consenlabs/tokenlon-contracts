// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IStrategy } from "./IStrategy.sol";

/// @title ISmartOrderStrategy Interface
/// @author imToken Labs
interface ISmartOrderStrategy is IStrategy {
    error ZeroInput();
    error EmptyOps();
    error InvalidMsgValue();
    error InvalidInputRatio();
    error NotFromGS();

    /// @dev The encoded operation list should be passed as `data` when calling `IStrategy.executeStrategy`
    struct Operation {
        address dest;
        address inputToken;
        uint128 inputRatio;
        uint128 dataOffset;
        uint256 value;
        bytes data;
    }
}
