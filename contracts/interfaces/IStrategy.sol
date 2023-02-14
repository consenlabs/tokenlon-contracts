// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

/// @title IStrategy Interface
/// @author imToken Labs
interface IStrategy {
    function executeStrategy(
        address srcToken,
        uint256 inputAmount,
        bytes calldata data
    ) external;
}
