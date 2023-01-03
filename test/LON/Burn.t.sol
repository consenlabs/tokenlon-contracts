// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/LON/Setup.t.sol";

contract TestLONBurn is TestLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotBurnMoreThanOwned() public {
        lon.mint(user, uint256(1e18));
        uint256 excessAmount = lon.balanceOf(user) + 1;
        vm.expectRevert("ERC20: burn amount exceeds balance");
        vm.prank(user);
        lon.burn(excessAmount);
    }

    function testBurn() public {
        uint256 burnAmount = 1e18;

        lon.mint(user, burnAmount);
        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        vm.prank(user);
        lon.burn(burnAmount);
        userLon.assertChange(-int256(burnAmount));
    }
}
