// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/MarketMakerProxy.sol";
import "contracts/RFQ.sol";
import "contracts/utils/SignatureValidator.sol";
import "test/mocks/MockERC1271Wallet.sol";
import "test/utils/BalanceSnapshot.sol";
import "test/utils/StrategySharedSetup.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";

contract RFQTest is StrategySharedSetup {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 constant BPS_MAX = 10000;
    event FillOrder(
        string source,
        bytes32 indexed transactionHash,
        bytes32 indexed orderHash,
        address indexed userAddr,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );

    uint256 userPrivateKey = uint256(1);
    uint256 makerPrivateKey = uint256(2);
    uint256 otherPrivateKey = uint256(3);

    address user = vm.addr(userPrivateKey);
    address maker = vm.addr(makerPrivateKey);
    address owner = makeAddr("owner");
    address feeCollector = makeAddr("feeCollector");
    address receiver = makeAddr("receiver");
    address[] wallet = [user, maker];

    MockERC1271Wallet mockERC1271Wallet;
    MarketMakerProxy marketMakerProxy;
    RFQ rfq;

    uint256 DEADLINE = block.timestamp + 1;
    RFQLibEIP712.Order DEFAULT_ORDER;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        if (!vm.envBool("DEPLOYED")) {
            // overwrite tokens with locally deployed mocks
            tokens = [weth, usdt, dai];
        }
        setUpSystemContracts();

        marketMakerProxy = new MarketMakerProxy(maker, maker, IWETH(address(weth)));
        vm.prank(maker, maker);
        marketMakerProxy.updateWithdrawWhitelist(maker, true);
        mockERC1271Wallet = new MockERC1271Wallet(user);

        // Deal 100 ETH to each account
        dealWallet({ wallet: wallet, amount: 100 ether });
        // Set user token balance and approve
        setEOABalanceAndApprove({ eoa: user, tokens: tokens, amount: 100 });
        // Set ERC1271 wallet token balance and approve
        setWalletContractBalanceAndApprove({ owner: user, walletContract: address(mockERC1271Wallet), tokens: tokens, amount: 100 });
        // Set maker token balance and approve
        setEOABalanceAndApprove({ eoa: maker, tokens: tokens, amount: 100 });
        // Set MMP token balance and approve
        setWalletContractBalanceAndApprove({ owner: maker, walletContract: address(marketMakerProxy), tokens: tokens, amount: 100 });
        // Deal ETH to WETH contract because it's balances are manipualted without actual ETH deposit
        deal(address(weth), weth.totalSupply());

        // Default order
        DEFAULT_ORDER = RFQLibEIP712.Order(
            user, // takerAddr
            maker, // makerAddr
            address(dai), // takerAssetAddr
            address(usdt), // makerAssetAddr
            100 * 1e18, // takerAssetAmount
            90 * 1e6, // makerAssetAmount
            receiver, // receiverAddr
            uint256(1234), // salt
            DEADLINE, // deadline
            0 // feeFactor
        );

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(address(this), "TestingContract");
        vm.label(address(marketMakerProxy), "MarketMakerProxy");
        vm.label(address(mockERC1271Wallet), "MockERC1271Wallet");
        vm.label(address(rfq), "RFQContract");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        rfq = new RFQ(owner, address(userProxy), address(weth), address(permanentStorage), address(spender), feeCollector);
        // Setup
        userProxy.upgradeRFQ(address(rfq), true);
        vm.startPrank(psOperator, psOperator);
        permanentStorage.upgradeRFQ(address(rfq));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(rfq), true);
        vm.stopPrank();
        return address(rfq);
    }

    function _setupDeployedStrategy() internal override {
        rfq = RFQ(payable(vm.envAddress("RFQ_ADDRESS")));
        owner = rfq.owner();
        feeCollector = rfq.feeCollector();
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupAllowance() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
            assertEq(tokens[i].allowance(address(mockERC1271Wallet), address(allowanceTarget)), type(uint256).max);
            assertEq(tokens[i].allowance(maker, address(allowanceTarget)), type(uint256).max);
            assertEq(tokens[i].allowance(address(marketMakerProxy), address(allowanceTarget)), type(uint256).max);
        }
    }

    function testSetupRFQ() public {
        assertEq(rfq.owner(), owner);
        assertEq(rfq.userProxy(), address(userProxy));
        assertEq(address(rfq.spender()), address(spender));
        assertEq(address(rfq.weth()), address(weth));
        assertEq(rfq.feeCollector(), feeCollector);
        assertEq(userProxy.rfqAddr(), address(rfq));
        assertEq(permanentStorage.rfqAddr(), address(rfq));
        assertTrue(spender.isAuthorized(address(rfq)));
    }

    /*********************************
     *     Test: upgradeSpender      *
     *********************************/

    function testCannotUpgradeSpenderByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rfq.upgradeSpender(user);
    }

    function testCannotUpgradeSpenderToZeroAddress() public {
        vm.expectRevert("Strategy: spender can not be zero address");
        vm.prank(owner, owner);
        rfq.upgradeSpender(address(0));
    }

    function testUpgradeSpender() public {
        vm.prank(owner, owner);
        rfq.upgradeSpender(user);
        assertEq(address(rfq.spender()), user);
    }

    /*********************************
     *   Test: set/close allowance   *
     *********************************/

    function testCannotSetAllowanceCloseAllowanceByNotOwner() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.startPrank(user);
        vm.expectRevert("not owner");
        rfq.setAllowance(allowanceTokenList, address(this));
        vm.expectRevert("not owner");
        rfq.closeAllowance(allowanceTokenList, address(this));
        vm.stopPrank();
    }

    function testSetAllowanceCloseAllowance() public {
        address[] memory allowanceTokenList = new address[](1);
        allowanceTokenList[0] = address(usdt);

        vm.prank(owner, owner);
        assertEq(usdt.allowance(address(rfq), address(this)), uint256(0));

        vm.prank(owner, owner);
        rfq.setAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(rfq), address(this)), type(uint256).max);

        vm.prank(owner, owner);
        rfq.closeAllowance(allowanceTokenList, address(this));
        assertEq(usdt.allowance(address(rfq), address(this)), uint256(0));
    }

    /*********************************
     *       Test: depositETH        *
     *********************************/

    function testCannotDepositETHByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rfq.depositETH();
    }

    function testDepositETH() public {
        deal(address(rfq), 1 ether);
        assertEq(address(rfq).balance, 1 ether);
        vm.prank(owner, owner);
        rfq.depositETH();
        assertEq(address(rfq).balance, uint256(0));
        assertEq(weth.balanceOf(address(rfq)), 1 ether);
    }

    /*********************************
     *     Test: setFeeCollector     *
     *********************************/

    function testCannotSetFeeCollectorByNotOwner() public {
        vm.prank(user);
        vm.expectRevert("not owner");
        rfq.setFeeCollector(user);
    }

    function testSetFeeCollector() public {
        vm.prank(owner, owner);
        rfq.setFeeCollector(user);
        assertEq(rfq.feeCollector(), user);
    }

    /*********************************
     *          Test: fill          *
     *********************************/

    function testCannotFillWithExpiredOrder() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        order.deadline = block.timestamp - 1;
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFill({ privateKey: otherPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        vm.expectRevert("RFQ: expired order");
        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);
    }

    function testCannotFillWithInvalidUserSig() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFill({ privateKey: otherPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        vm.expectRevert("RFQ: invalid user signature");
        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);
    }

    function testCannotFillWithInvalidUserWallet() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        // Taker is an EOA but user signs a Wallet type fill
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.WalletBytes32 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        vm.expectRevert(); // No revert string in this case
        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);
    }

    function testCannotFillWithInvalidMakerSig() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSig = _signOrder({ privateKey: otherPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        vm.expectRevert("RFQ: invalid MM signature");
        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);
    }

    function testFillDAIToUSDT_EOAUserAndEOAMaker() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take({ owner: user, token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take({ owner: receiver, token: order.makerAssetAddr });
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take({ owner: maker, token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take({ owner: maker, token: order.makerAssetAddr });

        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        receiverMakerAsset.assertChange(int256(order.makerAssetAmount));
        makerTakerAsset.assertChange(int256(order.takerAssetAmount));
        makerMakerAsset.assertChange(-int256(order.makerAssetAmount));
    }

    function testFillDAIToUSDT_EOAUserAndEOAMaker_WithOldEIP712Method() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSig = _signOrderWithOldEIP712Method({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFillWithOldEIP712Method({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take({ owner: user, token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take({ owner: receiver, token: order.makerAssetAddr });
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take({ owner: maker, token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take({ owner: maker, token: order.makerAssetAddr });

        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        receiverMakerAsset.assertChange(int256(order.makerAssetAmount));
        makerTakerAsset.assertChange(int256(order.takerAssetAmount));
        makerMakerAsset.assertChange(-int256(order.makerAssetAmount));
    }

    function testFillETHToUSDT_EOAUserAndMMPMaker() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        order.takerAssetAddr = address(weth);
        order.takerAssetAmount = 1 ether;
        order.makerAddr = address(marketMakerProxy);
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.WalletBytes32 });
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take({ owner: user, token: ETH_ADDRESS });
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take({ owner: receiver, token: order.makerAssetAddr });
        BalanceSnapshot.Snapshot memory makerMMPTakerAsset = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory makerMMPMakerAsset = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: order.makerAssetAddr });

        vm.prank(user, user); // Only EOA
        userProxy.toRFQ{ value: order.takerAssetAmount }(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        receiverMakerAsset.assertChange(int256(order.makerAssetAmount));
        makerMMPTakerAsset.assertChange(int256(order.takerAssetAmount));
        makerMMPMakerAsset.assertChange(-int256(order.makerAssetAmount));
    }

    function testFillDAIToETH_WalletUserAndMMPMaker() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        order.takerAddr = address(mockERC1271Wallet);
        order.makerAddr = address(marketMakerProxy);
        order.makerAssetAddr = address(weth);
        order.makerAssetAmount = 1 ether;
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.WalletBytes32 });
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.WalletBytes32 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        BalanceSnapshot.Snapshot memory userWalletTakerAsset = BalanceSnapshot.take({ owner: address(mockERC1271Wallet), token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take({ owner: receiver, token: ETH_ADDRESS });
        BalanceSnapshot.Snapshot memory makerMMPTakerAsset = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory makerMMPMakerAsset = BalanceSnapshot.take({ owner: address(marketMakerProxy), token: order.makerAssetAddr });

        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);

        userWalletTakerAsset.assertChange(-int256(order.takerAssetAmount));
        receiverMakerAsset.assertChange(int256(order.makerAssetAmount));
        makerMMPTakerAsset.assertChange(int256(order.takerAssetAmount));
        makerMMPMakerAsset.assertChange(-int256(order.makerAssetAmount));
    }

    function testFillAccrueFeeToFeeCollector() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        order.feeFactor = 1000; // 10% fee
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take({ owner: user, token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take({ owner: receiver, token: order.makerAssetAddr });
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take({ owner: maker, token: order.takerAssetAddr });
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take({ owner: maker, token: order.makerAssetAddr });
        BalanceSnapshot.Snapshot memory feeCollectorMakerAsset = BalanceSnapshot.take({ owner: feeCollector, token: order.makerAssetAddr });

        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        receiverMakerAsset.assertChange(int256(order.makerAssetAmount.mul(90).div(100))); // 10% fee taken from maker asset
        makerTakerAsset.assertChange(int256(order.takerAssetAmount));
        makerMakerAsset.assertChange(-int256(order.makerAssetAmount));
        feeCollectorMakerAsset.assertChange(int256(order.makerAssetAmount.mul(10).div(100))); // 10% fee
    }

    function testCannotFillWithSamePayloadAgain() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);

        vm.expectRevert("PermanentStorage: transaction seen before");
        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);
    }

    /*********************************
     *       Test: emit event        *
     *********************************/

    function _expectEvent(RFQLibEIP712.Order memory order) internal {
        vm.expectEmit(true, true, true, true);
        emit FillOrder(
            "RFQ v1",
            RFQLibEIP712._getTransactionHash(order),
            RFQLibEIP712._getOrderHash(order),
            order.takerAddr,
            order.takerAssetAddr,
            order.takerAssetAmount,
            order.makerAddr,
            order.makerAssetAddr,
            order.makerAssetAmount,
            order.receiverAddr,
            order.makerAssetAmount.mul((BPS_MAX).sub(order.feeFactor)).div(BPS_MAX),
            uint16(order.feeFactor)
        );
    }

    function testEmitSwappedEvent() public {
        RFQLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory makerSig = _signOrder({ privateKey: makerPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory userSig = _signFill({ privateKey: userPrivateKey, order: order, sigType: SignatureValidator.SignatureType.EIP712 });
        bytes memory payload = _genFillPayload({ order: order, makerSig: makerSig, userSig: userSig });

        _expectEvent(order);
        vm.prank(user, user); // Only EOA
        userProxy.toRFQ(payload);
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function _signOrder(
        uint256 privateKey,
        RFQLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = RFQLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), orderHash);

        if (sigType == SignatureValidator.SignatureType.EIP712) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
            sig = abi.encodePacked(r, s, v, uint8(sigType));
        } else if (
            sigType == SignatureValidator.SignatureType.Wallet ||
            sigType == SignatureValidator.SignatureType.WalletBytes ||
            sigType == SignatureValidator.SignatureType.WalletBytes32
        ) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toEthSignedMessageHash(EIP712SignDigest));
            sig = abi.encodePacked(r, s, v, uint8(sigType));
        } else {
            revert("Invalid signature type");
        }
    }

    function _signOrderWithOldEIP712Method(
        uint256 privateKey,
        RFQLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = RFQLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), orderHash);

        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }

    function _signFill(
        uint256 privateKey,
        RFQLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 transactionHash = RFQLibEIP712._getTransactionHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), transactionHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, uint8(sigType));
    }

    function _signFillWithOldEIP712Method(
        uint256 privateKey,
        RFQLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 transactionHash = RFQLibEIP712._getTransactionHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(rfq.EIP712_DOMAIN_SEPARATOR(), transactionHash);

        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }

    function _genFillPayload(
        RFQLibEIP712.Order memory order,
        bytes memory makerSig,
        bytes memory userSig
    ) internal view returns (bytes memory payload) {
        return abi.encodeWithSelector(rfq.fill.selector, order, makerSig, userSig);
    }
}
