// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/AllowanceTarget/Setup.t.sol";

contract TestAllowanceTargetConstructor is TestAllowanceTarget {
    function testCannotConstructByZeroAddress() public {
        vm.expectRevert("AllowanceTarget: _spender should not be 0");
        allowanceTarget = new AllowanceTarget(address(0));
    }

    // normal case
    function testConstructor() public {
        assertEq(allowanceTarget.spender(), address(this));
    }
}
