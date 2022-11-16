// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/RFQLibEIP712.sol";
import "../utils/SpenderLibEIP712.sol";

/// @title IRFQ Interface
/// @author imToken Labs
interface IRFQ is IStrategyBase {
    /// @notice Fill an order
    /// @notice Only order with correct signatures of taker and maker can be filled and filled only once
    /// @param _order The order that is going to be filled
    /// @param _mmSignature The signature of the order from maker
    /// @param _userSignature The signature of the order from taker
    /// @return The settled amount of the order
    function fill(
        RFQLibEIP712.Order calldata _order,
        bytes calldata _mmSignature,
        bytes calldata _userSignature,
        bytes calldata _makerAssetPermitSig,
        bytes calldata _takerAssetPermitSig
    ) external payable returns (uint256);
}
