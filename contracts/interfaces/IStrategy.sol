// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IStrategy Interface
/// @author imToken Labs
interface IStrategy {
    function executeStrategy(
        address srcToken,
        uint256 inputAmount,
        address targetToken,
        address[] calldata opTargets,
        bytes[] calldata ops
    ) external;
}
