// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";

contract TestLONStakingSetCooldownAndRageExitParam is TestLONStaking {
    function testCannotSetByNotOwner() public {
        vm.expectRevert("not owner");
        lonStaking.setCooldownAndRageExitParam(COOLDOWN_IN_DAYS, BPS_RAGE_EXIT_PENALTY);
    }

    function testCannotSetWithInvalidParam() public {
        vm.startPrank(stakingOwner);
        vm.expectRevert("COOLDOWN_IN_DAYS less than 1 day");
        lonStaking.setCooldownAndRageExitParam(0, BPS_RAGE_EXIT_PENALTY);
        vm.expectRevert("BPS_RAGE_EXIT_PENALTY larger than BPS_MAX");
        lonStaking.setCooldownAndRageExitParam(COOLDOWN_IN_DAYS, BPS_MAX + 1);
        vm.stopPrank();
    }

    function testSetCooldownAndRageExitParam() public {
        vm.startPrank(stakingOwner);
        lonStaking.setCooldownAndRageExitParam(COOLDOWN_IN_DAYS * 2, BPS_RAGE_EXIT_PENALTY * 2);
        assertEq(lonStaking.COOLDOWN_IN_DAYS(), COOLDOWN_IN_DAYS * 2);
        assertEq(lonStaking.BPS_RAGE_EXIT_PENALTY(), BPS_RAGE_EXIT_PENALTY * 2);
        vm.stopPrank();
    }
}
