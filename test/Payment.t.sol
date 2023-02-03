// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { Test } from "forge-std/Test.sol";

contract TestPayment is Test {
    function setUp() public virtual {
        vm.label(address(this), "TestingContract");
    }

    function testCanary() public {
        assertTrue(true);
    }
}

