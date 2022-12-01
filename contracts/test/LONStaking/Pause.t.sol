// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";

contract TestLONStakingPause is TestLONStaking {
    function testCannotPauseByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        lonStaking.pause();
    }

    function testCannotUnpauseByNotOwner() public {
        lonStaking.pause();

        vm.expectRevert("not owner");
        vm.prank(user);
        lonStaking.unpause();
    }

    function testPause() public {
        lonStaking.pause();
        assertTrue(lonStaking.paused());
    }

    function testUnpause() public {
        lonStaking.pause();
        lonStaking.unpause();
        assertFalse(lonStaking.paused());
    }
}
