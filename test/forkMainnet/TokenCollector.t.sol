// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { TokenCollector } from "contracts/utils/TokenCollector.sol";
import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { MockERC20Permit } from "test/mocks/MockERC20Permit.sol";
import { Addresses } from "test/utils/Addresses.sol";
import { getPermitSingleStructHash, getPermitTransferFromStructHash, encodePermitSingleData, encodePermitTransferFromData } from "test/utils/Permit2.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { StrategySharedSetup } from "test/utils/StrategySharedSetup.sol";

contract Strategy is TokenCollector {
    constructor(address _uniswapPermit2, address _tokenlonSpender) TokenCollector(_uniswapPermit2, _tokenlonSpender) {}

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

contract TestTokenCollector is StrategySharedSetup {
    struct TokenPermit {
        address token;
        address owner;
        address spender;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
    }

    bytes4 public constant SignatureExpiredErrorSig = 0xcd21db4f;
    uint256 otherPrivateKey = uint256(123);
    uint256 userPrivateKey = uint256(1);
    address user = vm.addr(userPrivateKey);

    MockERC20Permit token = new MockERC20Permit("Token", "TKN", 18);
    IUniswapPermit2 permit2 = IUniswapPermit2(UNISWAP_PERMIT2_ADDRESS);

    Strategy strategy;

    TokenPermit DEFAULT_TOKEN_PERMIT;
    IUniswapPermit2.PermitSingle DEFAULT_PERMIT_SINGLE;
    IUniswapPermit2.PermitTransferFrom DEFAULT_PERMIT_TRANSFER;

    function setUp() public {
        // Setup
        setUpSystemContracts();

        token.mint(user, 10000 * 1e18);

        strategy = new Strategy(address(permit2), address(spender));
        address[] memory authListAddress = new address[](1);
        authListAddress[0] = address(strategy);
        spender.authorize(authListAddress);

        DEFAULT_TOKEN_PERMIT = TokenPermit({
            token: address(token),
            owner: user,
            spender: address(strategy),
            amount: 100 * 1e18,
            nonce: token.nonces(user),
            deadline: block.timestamp + 1 days
        });

        DEFAULT_PERMIT_SINGLE = IUniswapPermit2.PermitSingle({
            details: IUniswapPermit2.PermitDetails({
                token: address(token),
                amount: 100 * 1e18,
                expiration: uint48(block.timestamp + 1 days),
                nonce: uint48(0)
            }),
            spender: address(strategy),
            sigDeadline: block.timestamp + 1 days
        });

        DEFAULT_PERMIT_TRANSFER = IUniswapPermit2.PermitTransferFrom({
            permitted: IUniswapPermit2.TokenPermissions({ token: address(token), amount: 100 * 1e18 }),
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        vm.label(address(this), "TestingContract");
        vm.label(address(token), "TKN");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        // only to avoid zero address error here
        return makeAddr("random strategy");
    }

    /* Token Approval */

    function testCannotCollectByTokenApprovalWhenAllowanceIsNotEnough() public {
        bytes memory data = abi.encode(TokenCollector.Source.Token, bytes(""));

        vm.expectRevert("ERC20: transfer amount exceeds allowance");
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
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        strategy.collect(address(token), permit.owner, address(this), permit.amount, data);
    }

    function testCannotCollectByTokenPermitWhenAmountIsMoreThanPermitted() public {
        TokenPermit memory permit = DEFAULT_TOKEN_PERMIT;
        // Amount is more than permitted
        uint256 invalidAmount = permit.amount + 100;

        bytes32 permitHash = getTokenPermitHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        bytes memory data = encodeTokenPermitData(permit, v, r, s);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
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

    /* Tokenlon Spender */

    function testCollectByTokenlonSpender() public {
        uint256 amount = 100 * 1e18;
        vm.prank(user);
        token.approve(address(allowanceTarget), amount);

        bytes memory data = abi.encode(TokenCollector.Source.TokenlonSpender, bytes(""));

        strategy.collect(address(token), user, address(this), amount, data);
    }

    function testCannotCollectByTokenlonSpenderWithoutPreApprove() public {
        uint256 amount = 100 * 1e18;
        bytes memory data = abi.encode(TokenCollector.Source.TokenlonSpender, bytes(""));

        vm.expectRevert("Spender: ERC20 transferFrom failed");
        strategy.collect(address(token), user, address(this), amount, data);
    }

    /* Permit2 Allowance Transfer */

    function signPermitSingle(uint256 privateKey, IUniswapPermit2.PermitSingle memory permit) private view returns (bytes memory) {
        bytes32 permitHash = getPermitSingleStructHash(permit);
        bytes32 EIP712SignDigest = getEIP712Hash(permit2.DOMAIN_SEPARATOR(), permitHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function testCannotCollectByPermit2AllowanceTransferWhenPermitSigIsInvalid() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;

        // Sign by not owner
        bytes memory permitSig = signPermitSingle(otherPrivateKey, permit);
        bytes memory data = encodePermitSingleData(permit, permitSig);

        vm.expectRevert(bytes4(keccak256("InvalidSigner()")));
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2AllowanceTransferWhenDeadlineIsExpired() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Permit is expired
        uint256 deadline = block.timestamp - 1 days;
        permit.details.expiration = uint48(deadline);
        permit.sigDeadline = deadline;

        bytes memory permitSig = signPermitSingle(userPrivateKey, permit);
        bytes memory data = encodePermitSingleData(permit, permitSig);

        vm.expectRevert(abi.encodeWithSelector(SignatureExpiredErrorSig, permit.sigDeadline));
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2AllowanceTransferWhenSpenderIsInvalid() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Spender is not strategy
        permit.spender = address(this);

        bytes memory permitSig = signPermitSingle(userPrivateKey, permit);
        bytes memory data = encodePermitSingleData(permit, permitSig);

        vm.expectRevert(bytes4(keccak256("InvalidSigner()")));
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2AllowanceTransferWhenAmountIsNotEqualToPermitted() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;

        bytes memory permitSig = signPermitSingle(userPrivateKey, permit);
        bytes memory data = encodePermitSingleData(permit, permitSig);

        // Amount is not equal to permitted
        uint256 invalidAmount = permit.details.amount + 100;
        vm.expectRevert(bytes4(keccak256("InvalidSigner()")));
        strategy.collect(address(token), user, address(this), invalidAmount, data);
    }

    function testCannotCollectByPermit2AllowanceTransferWhenNonceIsInvalid() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;
        // Nonce is invalid
        permit.details.nonce = 123;

        bytes memory permitSig = signPermitSingle(userPrivateKey, permit);
        bytes memory data = encodePermitSingleData(permit, permitSig);

        vm.expectRevert(bytes4(keccak256("InvalidNonce()")));
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCannotCollectByPermit2AllowanceTransferWhenAllowanceIsNotEnough() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;

        bytes memory permitSig = signPermitSingle(userPrivateKey, permit);
        bytes memory data = encodePermitSingleData(permit, permitSig);

        // Permit2 uses "solmate/src/utils/SafeTransferLib.sol" for safe transfer library
        vm.expectRevert("TRANSFER_FROM_FAILED");
        strategy.collect(address(token), user, address(this), permit.details.amount, data);
    }

    function testCollectByPermit2AllowanceTransfer() public {
        IUniswapPermit2.PermitSingle memory permit = DEFAULT_PERMIT_SINGLE;

        vm.prank(user);
        token.approve(address(permit2), permit.details.amount);

        bytes memory permitSig = signPermitSingle(userPrivateKey, permit);
        bytes memory data = encodePermitSingleData(permit, permitSig);

        strategy.collect(address(token), user, address(this), permit.details.amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, permit.details.amount);
    }

    /* Permit2 Signature Transfer */

    function signPermitTransferFrom(
        uint256 privateKey,
        IUniswapPermit2.PermitTransferFrom memory permit,
        address spender
    ) private view returns (bytes memory) {
        bytes32 permitHash = getPermitTransferFromStructHash(permit, spender);
        bytes32 EIP712SignDigest = getEIP712Hash(permit2.DOMAIN_SEPARATOR(), permitHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function testCannotCollectByPermit2SignatureTransferWhenSpenderIsInvalid() public {
        IUniswapPermit2.PermitTransferFrom memory permit = DEFAULT_PERMIT_TRANSFER;
        // Spender is not strategy
        address spender = address(this);

        bytes memory permitSig = signPermitTransferFrom(userPrivateKey, permit, spender);
        bytes memory data = encodePermitTransferFromData(permit, permitSig);

        vm.expectRevert(bytes4(keccak256("InvalidSigner()")));
        strategy.collect(address(token), user, address(this), permit.permitted.amount, data);
    }

    function testCannotCollectByPermit2SignatureTransferWhenAmountIsNotEqualToPermitted() public {
        IUniswapPermit2.PermitTransferFrom memory permit = DEFAULT_PERMIT_TRANSFER;

        bytes memory permitSig = signPermitTransferFrom(userPrivateKey, permit, address(strategy));
        bytes memory data = encodePermitTransferFromData(permit, permitSig);

        // Amount is not equal to permitted
        uint256 invalidAmount = permit.permitted.amount + 100;
        vm.expectRevert(bytes4(keccak256("InvalidSigner()")));
        strategy.collect(address(token), user, address(this), invalidAmount, data);
    }

    function testCannotCollectByPermit2SignatureTransferWhenNonceIsUsed() public {
        IUniswapPermit2.PermitTransferFrom memory permit = DEFAULT_PERMIT_TRANSFER;

        vm.prank(user);
        token.approve(address(permit2), permit.permitted.amount);

        bytes memory permitSig = signPermitTransferFrom(userPrivateKey, permit, address(strategy));
        bytes memory data = encodePermitTransferFromData(permit, permitSig);

        strategy.collect(address(token), user, address(this), permit.permitted.amount, data);

        // Reuse previous nonce
        vm.expectRevert(bytes4(keccak256("InvalidNonce()")));
        strategy.collect(address(token), user, address(this), permit.permitted.amount, data);
    }

    function testCannotCollectByPermit2SignatureTransferWhenDeadlineIsExpired() public {
        IUniswapPermit2.PermitTransferFrom memory permit = DEFAULT_PERMIT_TRANSFER;
        // Deadline is expired
        permit.deadline = block.timestamp - 1 days;

        bytes memory permitSig = signPermitTransferFrom(userPrivateKey, permit, address(strategy));
        bytes memory data = encodePermitTransferFromData(permit, permitSig);

        vm.expectRevert(abi.encodeWithSelector(SignatureExpiredErrorSig, permit.deadline));
        strategy.collect(address(token), user, address(this), permit.permitted.amount, data);
    }

    function testCollectByPermit2SignatureTransfer() public {
        IUniswapPermit2.PermitTransferFrom memory permit = DEFAULT_PERMIT_TRANSFER;

        vm.prank(user);
        token.approve(address(permit2), permit.permitted.amount);

        bytes memory permitSig = signPermitTransferFrom(userPrivateKey, permit, address(strategy));
        bytes memory data = encodePermitTransferFromData(permit, permitSig);

        strategy.collect(address(token), user, address(this), permit.permitted.amount, data);

        uint256 balance = token.balanceOf(address(this));
        assertEq(balance, permit.permitted.amount);
    }
}
