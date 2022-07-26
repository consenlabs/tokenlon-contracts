// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts-test/LONStaking/Setup.t.sol";
import "contracts/interfaces/ILon.sol";

contract TestLONStakingSetup is TestLONStaking {
    function testLONStakingSetup() public {
        assertEq(lonStaking.owner(), address(this));
        assertEq(address(lonStaking.lonToken()), address(lon));
        assertEq(lonStaking.COOLDOWN_IN_DAYS(), COOLDOWN_IN_DAYS);
        assertEq(lonStaking.BPS_RAGE_EXIT_PENALTY(), BPS_RAGE_EXIT_PENALTY);
    }

    /*********************************
     *     Test setup: initialize    *
     *********************************/

    function testCannotReinitialize() public {
        vm.expectRevert("Ownable already initialized");
        lonStaking.initialize(ILon(lon), user, COOLDOWN_IN_DAYS, BPS_RAGE_EXIT_PENALTY);
    }

    /*********************************
     *   Test setup: upgrade prxoy   *
     *********************************/

    function testCannotUpgradeProxyByNotAdmin() public {
        vm.expectRevert();
        vm.prank(user);
        xLon.upgradeTo(address(lon));
    }

    function testUpgradeProxy() public {
        vm.startPrank(upgradeAdmin);
        xLon.upgradeTo(address(lon));
        address newImpl = xLon.implementation();
        assertEq(newImpl, address(lon));
        vm.stopPrank();
    }
}
