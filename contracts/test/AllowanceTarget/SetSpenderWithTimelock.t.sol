// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/AllowanceTarget/Setup.t.sol";

contract TestAllowanceTargetSetSpenderWithTimeock is TestAllowanceTarget {
    function testCannotSetByRandomEOA() public {
        vm.prank(bob);
        vm.expectRevert("AllowanceTarget: not the spender");
        allowanceTarget.setSpenderWithTimelock(newSpender);
    }

    function testCannotSetByInvalidAddress() public {
        vm.expectRevert("AllowanceTarget: new spender not a contract");
        allowanceTarget.setSpenderWithTimelock(bob);
    }

    function testCannotSetInProgress() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        address mySpender = address(new MockStrategy());
        vm.expectRevert("AllowanceTarget: SetSpender in progress");
        allowanceTarget.setSpenderWithTimelock(mySpender);
    }

    // normal case
    function testSetSpenderWithTimeock() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        assertEq(allowanceTarget.newSpender(), newSpender);
        assertEq(allowanceTarget.timelockExpirationTime(), block.timestamp + 1 days);
    }
}
