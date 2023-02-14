// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { SignatureValidator } from "contracts/utils/SignatureValidator.sol";
import { TokenCollector } from "contracts/TokenCollector.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { MockERC20Permit } from "test/mocks/MockERC20Permit.sol";
import { Addresses } from "test/utils/Addresses.sol";

contract Strategy is TokenCollector {
    constructor(address _uniswapPermit2) TokenCollector(_uniswapPermit2) {}

    function collect(
        address token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external {
        _collect(token, from, to, amount, data);
    }
}

contract TestTokenCollector is Addresses {
    uint256 userPrivateKey = uint256(1);
    address user = vm.addr(userPrivateKey);

    MockERC20Permit token = new MockERC20Permit("Token", "TKN", 18);

    Strategy strategy = new Strategy(UNISWAP_PERMIT2_ADDRESS);

    function setUp() public {
        token.mint(user, 10000 * 1e18);

        vm.label(address(this), "TestingContract");
        vm.label(address(token), "TKN");
    }

    /* Token */

    function testCollectByTokenApproval() public {
        uint256 amount = 100 * 1e18;

        vm.prank(user);
        token.approve(address(strategy), amount);

        bytes memory data = abi.encode(TokenCollector.Source.Token, bytes(""));
        strategy.collect(address(token), user, address(this), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }

    function testCollectByTokenPermit() public {
        uint256 amount = 100 * 1e18;

        uint256 nonce = token.nonces(user);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 structHash = keccak256(abi.encode(token._PERMIT_TYPEHASH(), user, address(strategy), amount, nonce, deadline));
        bytes32 permitHash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = abi.encode(TokenCollector.Source.Token, abi.encode(user, address(strategy), amount, deadline, v, r, s));
        strategy.collect(address(token), user, address(this), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }

    /* Permit2 */

    bytes32 constant PERMIT_DETAILS_TYPEHASH = keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 constant PERMIT_SINGLE_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    function testCollectByUniswapPermit2() public {
        uint256 amount = 100 * 1e18;

        vm.prank(user);
        token.approve(UNISWAP_PERMIT2_ADDRESS, amount);

        IUniswapPermit2.PermitSingle memory permit = IUniswapPermit2.PermitSingle({
            details: IUniswapPermit2.PermitDetails({
                token: address(token),
                amount: uint160(amount),
                expiration: uint48(block.timestamp + 1 days),
                nonce: uint48(0)
            }),
            spender: address(strategy),
            sigDeadline: block.timestamp + 1 days
        });

        bytes32 structHashPermitDetails = keccak256(abi.encode(PERMIT_DETAILS_TYPEHASH, permit.details));
        bytes32 structHash = keccak256(abi.encode(PERMIT_SINGLE_TYPEHASH, structHashPermitDetails, permit.spender, permit.sigDeadline));
        bytes32 permitHash = keccak256(abi.encodePacked("\x19\x01", IUniswapPermit2(UNISWAP_PERMIT2_ADDRESS).DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);
        bytes memory permitSig = abi.encodePacked(r, s, v);

        bytes memory data = abi.encode(TokenCollector.Source.UniswapPermit2, abi.encode(user, permit, permitSig));
        strategy.collect(address(token), user, address(this), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }
}
