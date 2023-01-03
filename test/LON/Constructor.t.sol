// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/LON/Setup.t.sol";

contract TestLONConstructor is TestLON {
    function testConstructor() public {
        assertEq(lon.owner(), address(this));
        assertEq(lon.minter(), address(this));
        assertEq(lon.emergencyRecipient(), emergencyRecipient);
    }
}
