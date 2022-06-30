// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/LON/Setup.t.sol";

contract TestLONBurn is TestLON {
    // include Snapshot struct from BalanceSnapshot
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotBurnMoreThanOwned() public {
        lon.mint(user, 1e18);
        uint256 excessAmount = lon.balanceOf(user) + 1;
        vm.expectRevert("ERC20: burn amount exceeds balance");
        vm.prank(user);
        lon.burn(excessAmount);
    }

    function testBurn() public {
        lon.mint(user, 1e18);
        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        vm.prank(user);
        lon.burn(1e18);
        userLon.assertChange(-int256(1e18));
    }
}
