// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { Test } from "forge-std/Test.sol";
import { Payment } from "contracts/utils/Payment.sol";
import { MockERC20Permit } from "test/mocks/MockERC20Permit.sol";

contract TestPayment is Test {
    uint256 userPrivateKey = uint256(1);
    address user = vm.addr(userPrivateKey);

    MockERC20Permit token = new MockERC20Permit("Token", "TKN", 18);

    function setUp() public virtual {
        token.mint(user, 10000 * 1e18);

        vm.label(address(this), "TestingContract");
        vm.label(address(token), "TKN");
    }

    function testCanary() public {
        assertTrue(true);
    }

    function testPayByTokenDirectlyApproval() public {
        uint256 amount = 100 * 1e18;

        vm.prank(user);
        token.approve(address(this), amount);

        bytes memory data = abi.encode(Payment.Type.Token, bytes(""));
        Payment.fulfill(user, address(token), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }

    function testPayByTokenPermit() public {
        uint256 amount = 100 * 1e18;

        uint256 nonce = token.nonces(user);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(abi.encode(token._PERMIT_TYPEHASH(), user, address(this), amount, nonce, deadline));
        bytes32 permitHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = abi.encode(Payment.Type.Token, abi.encode(user, address(this), amount, deadline, v, r, s));
        Payment.fulfill(user, address(token), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }
}
