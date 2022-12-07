// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";

contract TestLONStakingPause is TestLONStaking {
    function testCannotPauseByNotOwner() public {
        vm.expectRevert("not owner");
        lonStaking.pause();
    }

    function testCannotUnpauseByNotOwner() public {
        vm.prank(stakingOwner);
        lonStaking.pause();

        vm.expectRevert("not owner");
        lonStaking.unpause();
    }

    function testPause() public {
        vm.prank(stakingOwner);
        lonStaking.pause();
        assertTrue(lonStaking.paused());
    }

    function testUnpause() public {
        vm.startPrank(stakingOwner);
        lonStaking.pause();
        lonStaking.unpause();
        vm.stopPrank();
        assertFalse(lonStaking.paused());
    }
}
