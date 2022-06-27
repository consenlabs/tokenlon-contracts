// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/AllowanceTarget/Setup.t.sol";

contract TestAllowanceTargetConstructor is TestAllowanceTarget {
    function testCannotAllowanceTargetConstructorByZeroAddress() public {
        vm.expectRevert("AllowanceTarget: _spender should not be 0");
        allowanceTarget = new AllowanceTarget(address(0));
    }

    // usually case
    function testAllowanceTargetConstructor() public {
        assertEq(allowanceTarget.spender(), address(this));
    }
}
