pragma solidity ^0.7.6;

contract MockStrategy {
    bool shouldFail;

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function execute() external {
        if (shouldFail) revert("Execution failed");
        return;
    }
}
