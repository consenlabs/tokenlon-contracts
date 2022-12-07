// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IAMMWrapper.sol";
import "../utils/AMMLibEIP712.sol";

/// @title IAMMWrapperWithPath Interface
/// @author imToken Labs
interface IAMMWrapperWithPath is IAMMWrapper {
    /// @notice Trade with AMM (specified path)
    /// @param _order The order details of this trade
    /// @param _feeFactor The factor used to calculate fee, only listed relayer can set it effectively
    /// @param _sig The signature of the trade from user
    /// @param _makerSpecificData The metadata required in this trade for specific AMM protocol
    /// @param _path The specified path data
    function trade(
        AMMLibEIP712.Order calldata _order,
        uint256 _feeFactor,
        bytes calldata _sig,
        bytes calldata _makerSpecificData,
        address[] calldata _path
    ) external payable returns (uint256);
}
