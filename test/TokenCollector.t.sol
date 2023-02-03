// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { Test } from "forge-std/Test.sol";
import { AllowanceTarget } from "contracts/AllowanceTarget.sol";
import { Spender } from "contracts/Spender.sol";
import { TokenCollector } from "contracts/TokenCollector.sol";
import { ITokenCollector } from "contracts/interfaces/ITokenCollector.sol";
import { MockERC20Permit } from "test/mocks/MockERC20Permit.sol";

contract TestPayment is Test {
    uint256 userPrivateKey = uint256(1);
    address user = vm.addr(userPrivateKey);

    MockERC20Permit token = new MockERC20Permit("Token", "TKN", 18);

    Spender spender = new Spender(address(this), new address[](0));
    AllowanceTarget allowanceTarget = new AllowanceTarget(address(spender));

    TokenCollector tokenCollector = new TokenCollector(address(spender));

    function setUp() public {
        spender.setAllowanceTarget(address(allowanceTarget));

        address[] memory authorizedList = new address[](1);
        authorizedList[0] = address(tokenCollector);
        spender.authorize(authorizedList);

        token.mint(user, 10000 * 1e18);

        vm.label(address(this), "TestingContract");
        vm.label(address(token), "TKN");
    }

    function testCollectByTokenApproval() public {
        uint256 amount = 100 * 1e18;

        vm.prank(user);
        token.approve(address(tokenCollector), amount);

        bytes memory data = abi.encode(ITokenCollector.Source.Token, bytes(""));
        tokenCollector.collect(address(token), user, address(this), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }

    function testCollectByTokenPermit() public {
        uint256 amount = 100 * 1e18;

        uint256 nonce = token.nonces(user);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(abi.encode(token._PERMIT_TYPEHASH(), user, address(tokenCollector), amount, nonce, deadline));
        bytes32 permitHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = abi.encode(ITokenCollector.Source.Token, abi.encode(user, address(tokenCollector), amount, deadline, v, r, s));
        tokenCollector.collect(address(token), user, address(this), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }

    function testCollectBySpenderApproval() public {
        uint256 amount = 100 * 1e18;

        vm.prank(user);
        token.approve(address(allowanceTarget), amount);

        bytes memory data = abi.encode(ITokenCollector.Source.Spender, bytes(""));
        tokenCollector.collect(address(token), user, address(this), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }
}
