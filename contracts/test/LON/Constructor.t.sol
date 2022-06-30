// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;

import "contracts-test/LON/Setup.t.sol";

contract TestLONConstructor is TestLON {
    // normal case
    function testConstructor() public {
        assertEq(lon.owner(), address(this));
        assertEq(lon.minter(), address(this));
        assertEq(lon.emergencyRecipient(), emergencyRecipient);
    }
}
