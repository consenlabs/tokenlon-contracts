// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "contracts/AllowanceTarget.sol";
import "test/mocks/MockStrategy.sol";

contract TestAllowanceTarget is Test {
    address newSpender = address(new MockStrategy());
    address bob = address(0x133701);

    AllowanceTarget allowanceTarget;

    // effectively a "beforeEach" block
    function setUp() public virtual {
        // Setup
        allowanceTarget = new AllowanceTarget(address(this));

        // Label addresses for easier debugging
        vm.label(address(this), "TestingContract");
        vm.label(address(allowanceTarget), "AllowanceTarget");
    }
}
