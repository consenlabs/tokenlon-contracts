// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IStrategy Interface
/// @author imToken Labs
interface IStrategy {
    function executeStrategy(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        bytes calldata data
    ) external payable;
}
