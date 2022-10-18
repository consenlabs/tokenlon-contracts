// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperUpgradeSpender is TestAMMWrapper {
    function testCannotUpgradeByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        ammWrapper.upgradeSpender(user);
    }

    function testCannotUpgradeToZeroAddress() public {
        vm.expectRevert("Strategy: spender can not be zero address");
        vm.prank(owner, owner);
        ammWrapper.upgradeSpender(address(0));
    }

    function testUpgradeSpender() public {
        vm.prank(owner, owner);
        ammWrapper.upgradeSpender(user);
        assertEq(address(ammWrapper.spender()), user);
    }
}
