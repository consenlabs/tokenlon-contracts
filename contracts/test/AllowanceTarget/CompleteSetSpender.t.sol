// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/AllowanceTarget/Setup.t.sol";

contract TestAllowanceTargetCompleteSetSpender is TestAllowanceTarget {
    function testCannotSetBeforeSetNew() public {
        vm.expectRevert("AllowanceTarget: no pending SetSpender");
        allowanceTarget.completeSetSpender();
    }

    function testCannotSetTooEarly() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        vm.expectRevert("AllowanceTarget: time lock not expired yet");
        allowanceTarget.completeSetSpender();
    }

    // normal case
    function testCompleteSetSpender() public {
        allowanceTarget.setSpenderWithTimelock(newSpender);
        // fast forward
        vm.warp(allowanceTarget.timelockExpirationTime());
        allowanceTarget.completeSetSpender();
        assertEq(allowanceTarget.spender(), newSpender);
    }
}
