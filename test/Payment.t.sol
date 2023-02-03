// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { Test } from "forge-std/Test.sol";
import { Payment } from "contracts/utils/Payment.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";

contract TestPayment is Test {
    uint256 userPrivateKey = uint256(1);
    address user = vm.addr(userPrivateKey);

    MockERC20 token = new MockERC20("Token", "TKN", 18);

    function setUp() public virtual {
        token.mint(user, 10000 * 1e18);

        vm.label(address(this), "TestingContract");
        vm.label(address(token), "TKN");
    }

    function testCanary() public {
        assertTrue(true);
    }

    function testPayByDirectlyApproval() public {
        uint256 amount = 100 * 1e18;

        vm.prank(user);
        token.approve(address(this), amount);

        bytes memory data = abi.encode(Payment.Type.Token, bytes(""));
        Payment.fulfill(user, address(token), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }
}
