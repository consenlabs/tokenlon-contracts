// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
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
    uint256 otherPrivateKey = uint256(123);
    uint256 userPrivateKey = uint256(1);
    address user = vm.addr(userPrivateKey);

    MockERC20Permit token = new MockERC20Permit("Token", "TKN", 18);

    Strategy strategy = new Strategy(UNISWAP_PERMIT2_ADDRESS);

    function setUp() public {
        token.mint(user, 10000 * 1e18);

        vm.label(address(this), "TestingContract");
        vm.label(address(token), "TKN");
    }

    /* Token Approval */

    function testCannotCollectByTokenApprovalWhenAllowanceIsNotEnough() public {
        bytes memory data = abi.encode(TokenCollector.Source.Token, bytes(""));

        vm.expectRevert("ERC20: insufficient allowance");
        strategy.collect(address(token), user, address(this), 1, data);
    }

    function testCollectByTokenApproval() public {
        uint256 amount = 100 * 1e18;

        vm.prank(user);
        token.approve(address(strategy), amount);

        bytes memory data = abi.encode(TokenCollector.Source.Token, bytes(""));
        strategy.collect(address(token), user, address(this), amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, amount);
    }

    /* Token Permit */

    TokenPermit DEFAULT_TOKEN_PERMIT =
        TokenPermit({
            token: address(token),
            owner: user,
            spender: address(strategy),
            amount: 100 * 1e18,
            nonce: token.nonces(user),
            deadline: block.timestamp + 1 days
        });

    struct TokenPermit {
        address token;
        address owner;
        address spender;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    function getTokenPermitHash(TokenPermit memory permit) private view returns (bytes32) {
        MockERC20Permit tokenWithPermit = MockERC20Permit(permit.token);
        bytes32 structHash = keccak256(
            abi.encode(tokenWithPermit._PERMIT_TYPEHASH(), permit.owner, permit.spender, permit.amount, permit.nonce, permit.deadline)
        );
        return keccak256(abi.encodePacked("\x19\x01", tokenWithPermit.DOMAIN_SEPARATOR(), structHash));
    }

    function encodeTokenPermitData(
        TokenPermit memory permit,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private pure returns (bytes memory) {
        return abi.encode(TokenCollector.Source.Token, abi.encode(permit.owner, permit.spender, permit.amount, permit.deadline, v, r, s));
    }

    function testCannotCollectByTokenPermitWhenPermitSigIsInvalid() public {
        TokenPermit memory permit = DEFAULT_TOKEN_PERMIT;

        bytes32 permitHash = getTokenPermitHash(permit);
        // Sign by not owner
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherPrivateKey, permitHash);

        bytes memory data = encodeTokenPermitData(permit, v, r, s);
        vm.expectRevert("ERC20Permit: invalid signature");
        strategy.collect(address(token), permit.owner, address(this), permit.amount, data);
    }

    function testCannotCollectByTokenPermitWhenSpenderIsInvalid() public {
        TokenPermit memory permit = DEFAULT_TOKEN_PERMIT;
        // Spender is not strategy
        permit.spender = address(this);

        bytes32 permitHash = getTokenPermitHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = encodeTokenPermitData(permit, v, r, s);
        vm.expectRevert("ERC20: insufficient allowance");
        strategy.collect(address(token), permit.owner, address(this), permit.amount, data);
    }

    function testCannotCollectByTokenPermitWhenAmountIsMoreThanPermitted() public {
        TokenPermit memory permit = DEFAULT_TOKEN_PERMIT;
        // Amount is more than permitted
        uint256 invalidAmount = permit.amount + 100;

        bytes32 permitHash = getTokenPermitHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = encodeTokenPermitData(permit, v, r, s);
        vm.expectRevert("ERC20: insufficient allowance");
        strategy.collect(address(token), permit.owner, address(this), invalidAmount, data);
    }

    function testCannotCollectByTokenPermitWhenNonceIsInvalid() public {
        TokenPermit memory permit = DEFAULT_TOKEN_PERMIT;
        // Nonce is invalid
        permit.nonce = 123;

        bytes32 permitHash = getTokenPermitHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = encodeTokenPermitData(permit, v, r, s);
        vm.expectRevert("ERC20Permit: invalid signature");
        strategy.collect(address(token), permit.owner, address(this), permit.amount, data);
    }

    function testCannotCollectByTokenPermitWhenDeadlineIsExpired() public {
        TokenPermit memory permit = DEFAULT_TOKEN_PERMIT;
        // Deadline is expired
        permit.deadline = block.timestamp - 1 days;

        bytes32 permitHash = getTokenPermitHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = encodeTokenPermitData(permit, v, r, s);
        vm.expectRevert("ERC20Permit: expired deadline");
        strategy.collect(address(token), permit.owner, address(this), permit.amount, data);
    }

    function testCollectByTokenPermit() public {
        TokenPermit memory permit = DEFAULT_TOKEN_PERMIT;

        bytes32 permitHash = getTokenPermitHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = encodeTokenPermitData(permit, v, r, s);
        strategy.collect(address(token), permit.owner, address(this), permit.amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, permit.amount);
    }

    /* Permit2 Allowance Transfer */

    bytes32 constant PERMIT_DETAILS_TYPEHASH = keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 constant PERMIT_SINGLE_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    IUniswapPermit2.PermitSingle DEFAULT_PERMIT_SINGLE =
        IUniswapPermit2.PermitSingle({
            details: IUniswapPermit2.PermitDetails({
                token: address(token),
                amount: 100 * 1e18,
                expiration: uint48(block.timestamp + 1 days),
                nonce: uint48(0)
            }),
            spender: address(strategy),
            sigDeadline: block.timestamp + 1 days
        });

    function getPermit2PermitHash(IUniswapPermit2.PermitSingle memory permit) private view returns (bytes32) {
        bytes32 structHashPermitDetails = keccak256(abi.encode(PERMIT_DETAILS_TYPEHASH, permit.details));
        bytes32 structHash = keccak256(abi.encode(PERMIT_SINGLE_TYPEHASH, structHashPermitDetails, permit.spender, permit.sigDeadline));
        return keccak256(abi.encodePacked("\x19\x01", IUniswapPermit2(UNISWAP_PERMIT2_ADDRESS).DOMAIN_SEPARATOR(), structHash));
    }

    function signPermit2(uint256 privateKey, bytes32 hash) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function encodePermit2Data(
        address owner,
        IUniswapPermit2.PermitSingle memory permit,
        bytes memory permitSig
    ) private pure returns (bytes memory) {
        return abi.encode(TokenCollector.Source.Permit2AllowanceTransfer, abi.encode(owner, permit, permitSig));
    }

    function testCannotCollectByPermit2WhenPermitSigIsInvalid() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;

        bytes32 permitHash = getPermit2PermitHash(permit);
        // Sign by not owner
        bytes memory permitSig = signPermit2(otherPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        vm.expectRevert(IUniswapPermit2.InvalidSigner.selector);
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2WhenPermitSigIsExpired() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Permit sig is expired
        permit.sigDeadline = block.timestamp - 1 days;

        bytes32 permitHash = getPermit2PermitHash(permit);
        bytes memory permitSig = signPermit2(userPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        vm.expectRevert(abi.encodeWithSelector(IUniswapPermit2.SignatureExpired.selector, permit.sigDeadline));
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2WhenSpenderIsInvalid() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Spender is not strategy
        permit.spender = address(this);

        bytes32 permitHash = getPermit2PermitHash(permit);
        bytes memory permitSig = signPermit2(userPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        vm.expectRevert(abi.encodeWithSelector(IUniswapPermit2.AllowanceExpired.selector, 0));
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2WhenAmountIsMoreThanPermitted() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Amount is more than permitted
        uint256 invalidAmount = permit.details.amount + 100;

        bytes32 permitHash = getPermit2PermitHash(permit);
        bytes memory permitSig = signPermit2(userPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        vm.expectRevert(abi.encodeWithSelector(IUniswapPermit2.InsufficientAllowance.selector, permit.details.amount));
        strategy.collect(address(token), user, address(this), invalidAmount, data);
    }

    function testCannotCollectByPermit2WhenNonceIsInvalid() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Nonce is invalid
        permit.details.nonce = 123;

        bytes32 permitHash = getPermit2PermitHash(permit);
        bytes memory permitSig = signPermit2(userPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        vm.expectRevert(IUniswapPermit2.InvalidNonce.selector);
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2WhenDetailIsExpired() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Detail is expired
        permit.details.expiration = uint48(block.timestamp - 1 days);

        bytes32 permitHash = getPermit2PermitHash(permit);
        bytes memory permitSig = signPermit2(userPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        vm.expectRevert(abi.encodeWithSelector(IUniswapPermit2.AllowanceExpired.selector, permit.details.expiration));
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2WhenAllowanceIsNotEnough() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;

        bytes32 permitHash = getPermit2PermitHash(permit);
        bytes memory permitSig = signPermit2(userPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        // Permit2 uses "solmate/src/utils/SafeTransferLib.sol" for safe transfer library
        vm.expectRevert("TRANSFER_FROM_FAILED");
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCollectByPermit2() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;

        vm.prank(user);
        token.approve(UNISWAP_PERMIT2_ADDRESS, permit.details.amount);

        bytes32 permitHash = getPermit2PermitHash(permit);
        bytes memory permitSig = signPermit2(userPrivateKey, permitHash);
        bytes memory data = encodePermit2Data(user, permit, permitSig);

        strategy.collect(address(token), user, address(this), permit.details.amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, permit.details.amount);
    }
}
