// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts-test/forkMainnet/AMMWrapper/Setup.t.sol";

contract TestAMMWrapperUpgradeSpender is TestAMMWrapper {
    function testCannotUpgradeSpenderByNotOperator() public {
        vm.expectRevert("AMMWrapper: not the operator");
        vm.prank(user);
        ammWrapper.upgradeSpender(user);
    }

    function testCannotUpgradeSpenderToZeroAddress() public {
        vm.expectRevert("AMMWrapper: spender can not be zero address");
        ammWrapper.upgradeSpender(address(0));
    }

    function testUpgradeSpender() public {
        ammWrapper.upgradeSpender(user);
        assertEq(address(ammWrapper.spender()), user);
    }
}
