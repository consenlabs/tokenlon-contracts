// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/LON/Setup.t.sol";

contract TestLONMint is TestLON {
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    function testCannotMintByNotMinter() public {
        vm.expectRevert("not minter");
        vm.prank(user);
        lon.mint(user, uint256(1e18));
    }

    function testCannotMintExceedCap() public {
        uint256 excessAmount = lon.cap() + 1;
        vm.expectRevert("cap exceeded");
        lon.mint(user, excessAmount);
    }

    function testCannotMintToZeroAddress() public {
        vm.expectRevert("zero address");
        lon.mint(address(0), uint256(1e18));
    }

    function testMint() public {
        uint256 mintAmount = 1e18;

        BalanceSnapshot.Snapshot memory userLon = BalanceSnapshot.take(user, address(lon));
        lon.mint(user, mintAmount);
        userLon.assertChange(int256(mintAmount));
    }
}
