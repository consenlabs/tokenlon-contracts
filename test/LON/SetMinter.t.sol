// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/LON/Setup.t.sol";

contract TestLONSetMinter is TestLON {
    function testCannotSetByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        lon.setMinter(user);
    }

    function testSetMinter() public {
        lon.setMinter(user);
        assertEq(address(lon.minter()), user);
    }
}
