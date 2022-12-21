// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "test/LONStaking/Setup.t.sol";

contract TestLONStakingUnstake is TestLONStaking {
    function testCannotUnstakeWithZeroAmount() public {
        vm.expectRevert("no share to unstake");
        vm.prank(other);
        lonStaking.unstake();
    }

    function testCannotUnstakeAgain() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);

        vm.prank(user);
        lonStaking.unstake();

        vm.expectRevert("already unstake");
        vm.prank(user);
        lonStaking.unstake();
    }

    function testUnstakeWhenPaused() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);

        lonStaking.pause();

        assertEq(lonStaking.stakersCooldowns(user), 0);
        vm.prank(user);
        lonStaking.unstake();
        assertEq(lonStaking.stakersCooldowns(user), block.timestamp);
    }

    function testUnstake() public {
        _stake(user, DEFAULT_STAKE_AMOUNT);

        assertEq(lonStaking.stakersCooldowns(user), 0);
        vm.prank(user);
        lonStaking.unstake();
        assertEq(lonStaking.stakersCooldowns(user), block.timestamp);
    }
}
