// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

contract MockStrategy {
    bool shouldFail;

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function execute() external view {
        if (shouldFail) revert("Execution failed");
        return;
    }
}
