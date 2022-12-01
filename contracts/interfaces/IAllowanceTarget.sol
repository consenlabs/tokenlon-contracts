// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

interface IAllowanceTarget {
    function setSpenderWithTimelock(address _newSpender) external;

    function completeSetSpender() external;

    function executeCall(address payable _target, bytes calldata _callData) external returns (bytes memory resultData);

    function teardown() external;
}
