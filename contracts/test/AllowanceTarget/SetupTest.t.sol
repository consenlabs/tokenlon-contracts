// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/AllowanceTarget/Setup.t.sol";

contract TestAllowanceTargetSetup is TestAllowanceTarget {
    function testAllowanceTargetSetup() public {
        assertEq(allowanceTarget.spender(), address(this));
    }

    function testCannotConstructByZeroAddress() public {
        vm.expectRevert("AllowanceTarget: _spender should not be 0");
        allowanceTarget = new AllowanceTarget(address(0));
    }
}
