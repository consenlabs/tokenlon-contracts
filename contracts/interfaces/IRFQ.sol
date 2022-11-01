// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/RFQLibEIP712.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQ is IStrategyBase {
    /// @notice Fill an order
    /// @notice Only confirmed order with correct signatures of taker and maker can be filled once
    /// @param _order The order that is going to be filled
    /// @param _mmSignature The signature of the order from maker
    /// @param _userSignature The signature of the order from taker
    /// @return The settle amount of the order
    function fill(
        RFQLibEIP712.Order memory _order,
        bytes memory _mmSignature,
        bytes memory _userSignature
    ) external payable returns (uint256);
}
