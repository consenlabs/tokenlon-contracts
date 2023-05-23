// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "contracts/PionexContract.sol";
import "contracts/interfaces/IPionexContract.sol";
import "contracts/utils/SignatureValidator.sol";
import "contracts/utils/PionexContractLibEIP712.sol";
import "contracts/utils/LibConstant.sol";

import "test/mocks/MockERC1271Wallet.sol";
import "test/utils/BalanceSnapshot.sol";
import "test/utils/StrategySharedSetup.sol";
import { computeMainnetEIP712DomainSeparator, getEIP712Hash } from "test/utils/Sig.sol";

contract PionexContractTest is StrategySharedSetup {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    event LimitOrderFilledByTrader(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        bytes32 allowFillHash,
        address recipient,
        IPionexContract.FillReceipt fillReceipt
    );

    uint256 pionexPrivateKey = uint256(1);
    uint256 makerPrivateKey = uint256(2);
    uint256 coordinatorPrivateKey = uint256(3);

    address pionex = vm.addr(pionexPrivateKey);
    address maker = vm.addr(makerPrivateKey);
    address coordinator = vm.addr(coordinatorPrivateKey);
    address owner = makeAddr("owner");
    address feeCollector = makeAddr("feeCollector");
    address receiver = makeAddr("receiver");
    MockERC1271Wallet mockERC1271Wallet = new MockERC1271Wallet(pionex);
    address[] wallet = [pionex, maker, coordinator, address(mockERC1271Wallet)];
    address[] allowanceAddrs;

    address[] DEFAULT_AMM_PATH;
    PionexContractLibEIP712.Order DEFAULT_ORDER;
    bytes32 DEFAULT_ORDER_HASH;
    bytes DEFAULT_ORDER_MAKER_SIG;
    PionexContractLibEIP712.Fill DEFAULT_FILL;
    PionexContractLibEIP712.AllowFill DEFAULT_ALLOW_FILL;
    uint16 DEFAULT_GAS_FEE_FACTOR = 0;
    uint16 DEFAULT_PIONEX_STRATEGY_FEE_FACTOR = 0;
    IPionexContract.TraderParams DEFAULT_TRADER_PARAMS;
    IPionexContract.CoordinatorParams DEFAULT_CRD_PARAMS;

    PionexContract pionexContract;
    uint64 DEADLINE = uint64(block.timestamp + 2 days);
    uint256 FACTORSDEALY = 12 hours;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        setUpSystemContracts();

        DEFAULT_AMM_PATH = [address(dai), address(usdt)];
        allowanceAddrs = DEFAULT_AMM_PATH;

        // Default params
        DEFAULT_ORDER = PionexContractLibEIP712.Order(
            dai, // makerToken
            usdt, // takerToken
            100 * 1e18, // makerTokenAmount
            90 * 1e6, // takerTokenAmount
            maker, // maker
            address(0), // taker
            uint256(1001), // salt
            DEADLINE // expiry
        );
        DEFAULT_ORDER_HASH = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), PionexContractLibEIP712._getOrderStructHash(DEFAULT_ORDER));
        DEFAULT_ORDER_MAKER_SIG = _signOrder(makerPrivateKey, DEFAULT_ORDER, SignatureValidator.SignatureType.EIP712);
        DEFAULT_FILL = PionexContractLibEIP712.Fill(
            DEFAULT_ORDER_HASH,
            pionex,
            receiver,
            DEFAULT_ORDER.makerTokenAmount,
            DEFAULT_ORDER.takerTokenAmount,
            uint256(1002),
            DEADLINE
        );
        DEFAULT_TRADER_PARAMS = IPionexContract.TraderParams(
            pionex, // taker
            receiver, // recipient
            DEFAULT_FILL.makerTokenAmount, // makerTokenAmount
            DEFAULT_FILL.takerTokenAmount, // takerTokenAmount
            DEFAULT_GAS_FEE_FACTOR, // gas fee factor
            DEFAULT_PIONEX_STRATEGY_FEE_FACTOR, // pionex strategy fee factor
            DEFAULT_FILL.takerSalt, // salt
            DEADLINE, // expiry
            _signFill(pionexPrivateKey, DEFAULT_FILL, SignatureValidator.SignatureType.EIP712) // takerSig
        );
        DEFAULT_ALLOW_FILL = PionexContractLibEIP712.AllowFill(
            DEFAULT_ORDER_HASH, // orderHash
            pionex, // executor
            DEFAULT_FILL.takerTokenAmount, // fillAmount
            uint256(1003), // salt
            DEADLINE // expiry
        );
        DEFAULT_CRD_PARAMS = IPionexContract.CoordinatorParams(
            _signAllowFill(coordinatorPrivateKey, DEFAULT_ALLOW_FILL, SignatureValidator.SignatureType.EIP712),
            DEFAULT_ALLOW_FILL.salt,
            DEFAULT_ALLOW_FILL.expiry
        );

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        tokens = [weth, usdt, dai];
        setEOABalanceAndApprove(pionex, tokens, 10000);
        setEOABalanceAndApprove(maker, tokens, 10000);
        setEOABalanceAndApprove(address(mockERC1271Wallet), tokens, 10000);

        // Label addresses for easier debugging
        vm.label(pionex, "Pionex");
        vm.label(maker, "Maker");
        vm.label(coordinator, "Coordinator");
        vm.label(receiver, "Receiver");
        vm.label(feeCollector, "FeeCollector");
        vm.label(address(this), "TestingContract");
        vm.label(address(pionexContract), "LimitOrderContract");
        vm.label(address(mockERC1271Wallet), "MockERC1271Wallet");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        pionexContract = new PionexContract(
            owner,
            address(userProxy),
            address(weth),
            address(permanentStorage),
            address(spender),
            coordinator,
            FACTORSDEALY,
            feeCollector
        );
        // Setup
        userProxy.upgradeLimitOrder(address(pionexContract), true);
        vm.startPrank(psOperator, psOperator);
        permanentStorage.upgradeLimitOrder(address(pionexContract));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(pionexContract), true);
        permanentStorage.setPermission(permanentStorage.allowFillSeenStorageId(), address(pionexContract), true);
        vm.stopPrank();
        return address(pionexContract);
    }

    function _setupDeployedStrategy() internal override {
        pionexContract = PionexContract(payable(vm.envAddress("LIMITORDER_ADDRESS")));

        // prank owner and update coordinator address
        owner = pionexContract.owner();
        vm.prank(owner, owner);
        pionexContract.upgradeCoordinator(coordinator);
        // update local feeCollector address
        feeCollector = pionexContract.feeCollector();
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupLimitOrder() public {
        assertEq(pionexContract.owner(), owner);
        assertEq(pionexContract.coordinator(), coordinator);
        assertEq(pionexContract.userProxy(), address(userProxy));
        assertEq(address(pionexContract.spender()), address(spender));
        assertEq(address(pionexContract.permStorage()), address(permanentStorage));
        assertEq(address(pionexContract.weth()), address(weth));

        assertEq(uint256(pionexContract.makerFeeFactor()), 0);
    }

    /*********************************
     *     Test: transferOwnership   *
     *********************************/

    function testCannotTransferOwnershipByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(pionex);
        pionexContract.nominateNewOwner(pionex);
    }

    function testCannotAcceptOwnershipIfNotNominated() public {
        vm.expectRevert("not nominated");
        vm.prank(pionex);
        pionexContract.acceptOwnership();
    }

    function testTransferOwnership() public {
        vm.prank(owner, owner);
        pionexContract.nominateNewOwner(pionex);
        vm.prank(pionex);
        pionexContract.acceptOwnership();
        assertEq(pionexContract.owner(), pionex);
    }

    /*********************************
     *     Test: upgradeSpender      *
     *********************************/

    function testCannotUpgradeSpenderByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(pionex);
        pionexContract.upgradeSpender(pionex);
    }

    function testCannotUpgradeSpenderToZeroAddr() public {
        vm.expectRevert("Strategy: spender can not be zero address");
        vm.prank(owner, owner);
        pionexContract.upgradeSpender(address(0));
    }

    function testUpgradeSpender() public {
        vm.prank(owner, owner);
        pionexContract.upgradeSpender(pionex);
        assertEq(address(pionexContract.spender()), pionex);
    }

    /*********************************
     *     Test: upgradeCoordinator  *
     *********************************/

    function testCannotUpgradeCoordinatorByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(pionex);
        pionexContract.upgradeCoordinator(pionex);
    }

    function testCannotUpgradeCoordinatorToZeroAddr() public {
        vm.expectRevert("LimitOrder: coordinator can not be zero address");
        vm.prank(owner, owner);
        pionexContract.upgradeCoordinator(address(0));
    }

    function testUpgradeCoordinator() public {
        vm.prank(owner, owner);
        pionexContract.upgradeCoordinator(pionex);
        assertEq(address(pionexContract.coordinator()), pionex);
    }

    /*********************************
     *   Test: set/close allowance   *
     *********************************/

    function testCannotSetAllowanceByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(pionex);
        pionexContract.setAllowance(allowanceAddrs, address(allowanceTarget));
    }

    function testCannotCloseAllowanceByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(pionex);
        pionexContract.closeAllowance(allowanceAddrs, address(allowanceTarget));
    }

    function testSetAndCloseAllowance() public {
        // Set allowance
        vm.prank(owner, owner);
        pionexContract.setAllowance(allowanceAddrs, address(allowanceTarget));
        assertEq(usdt.allowance(address(pionexContract), address(allowanceTarget)), LibConstant.MAX_UINT);
        assertEq(dai.allowance(address(pionexContract), address(allowanceTarget)), LibConstant.MAX_UINT);

        // Close allowance
        vm.prank(owner, owner);
        pionexContract.closeAllowance(allowanceAddrs, address(allowanceTarget));
        assertEq(usdt.allowance(address(pionexContract), address(allowanceTarget)), 0);
        assertEq(dai.allowance(address(pionexContract), address(allowanceTarget)), 0);
    }

    /*********************************
     *        Test: depoitETH        *
     *********************************/

    function testCannotDepositETHByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(pionex);
        pionexContract.depositETH();
    }

    function testDepositETH() public {
        // Send ether to limit order contract
        uint256 amount = 1234 ether;
        deal(address(pionexContract), amount);
        vm.prank(owner, owner);
        pionexContract.depositETH();
        assertEq(weth.balanceOf(address(pionexContract)), amount);
    }

    /*********************************
     *        Test: setFactors       *
     *********************************/

    function testCannotSetFactorsIfLargerThanBpsMax() public {
        vm.expectRevert("LimitOrder: Invalid maker fee factor");
        vm.prank(owner, owner);
        pionexContract.setFactors(LibConstant.BPS_MAX + 1);
    }

    function testSetFactors() public {
        vm.startPrank(owner, owner);
        pionexContract.setFactors(1);
        // fee factors should stay same before new ones activate
        assertEq(uint256(pionexContract.makerFeeFactor()), 0);
        vm.warp(block.timestamp + pionexContract.factorActivateDelay());

        // fee factors should be updated now
        pionexContract.activateFactors();
        vm.stopPrank();
        assertEq(uint256(pionexContract.makerFeeFactor()), 1);
    }

    /*********************************
     *     Test: setFeeCollector     *
     *********************************/

    function testCannotSetFeeCollectorByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(pionex);
        pionexContract.setFeeCollector(feeCollector);
    }

    function testCannotSetFeeCollectorToZeroAddr() public {
        vm.expectRevert("LimitOrder: fee collector can not be zero address");
        vm.prank(owner, owner);
        pionexContract.setFeeCollector(address(0));
    }

    function testSetFeeCollector() public {
        vm.prank(owner, owner);
        pionexContract.setFeeCollector(pionex);
        assertEq(address(pionexContract.feeCollector()), pionex);
    }

    /*********************************
     *  Test: fillLimitOrderByTrader *
     *********************************/

    function testCannotFillByTraderIfNotFromUserProxy() public {
        vm.expectRevert("Strategy: not from UserProxy contract");
        // Call limit order contract directly will get reverted since msg.sender is not from UserProxy
        pionexContract.fillLimitOrderByTrader(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
    }

    function testCannotFillFilledOrderByTrader() public {
        // Fullly fill the default order first
        bytes memory payload1 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload1);

        // Try to fill the default order, should fail
        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.takerSalt = uint256(8001);

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);
        traderParams.salt = fill.takerSalt;

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.salt = uint256(8002);

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);
        crdParams.salt = allowFill.salt;

        bytes memory payload2 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
        vm.expectRevert("LimitOrder: Order is filled");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload2);
    }

    function testCannotFillExpiredOrderByTrader() public {
        PionexContractLibEIP712.Order memory order = DEFAULT_ORDER;
        order.expiry = uint64(block.timestamp - 1);

        bytes32 orderHash = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), PionexContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrder(makerPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(order, orderMakerSig, traderParams, crdParams);
        vm.expectRevert("LimitOrder: Order is expired");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithWrongMakerSig() public {
        bytes memory wrongMakerSig = _signOrder(pionexPrivateKey, DEFAULT_ORDER, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, wrongMakerSig, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
        vm.expectRevert("LimitOrder: Order is not signed by maker");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithWrongTakerSig() public {
        IPionexContract.TraderParams memory wrongTraderParams = DEFAULT_TRADER_PARAMS;
        wrongTraderParams.takerSig = _signFill(makerPrivateKey, DEFAULT_FILL, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, wrongTraderParams, DEFAULT_CRD_PARAMS);
        vm.expectRevert("LimitOrder: Fill is not signed by taker");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithTakerOtherThanOrderSpecified() public {
        PionexContractLibEIP712.Order memory order = DEFAULT_ORDER;
        // order specify taker address
        order.taker = coordinator;
        bytes32 orderHash = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), PionexContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrder(makerPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        // pionex try to fill this order
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(order, orderMakerSig, traderParams, crdParams);
        vm.expectRevert("LimitOrder: Order cannot be filled by this taker");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithExpiredFill() public {
        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.expiry = uint64(block.timestamp - 1);

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);
        traderParams.expiry = fill.expiry;

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
        vm.expectRevert("LimitOrder: Fill request is expired");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotReplayFill() public {
        // Fill with DEFAULT_FILL
        bytes memory payload1 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload1);

        // Try to fill with same fill request with differnt allowFill (otherwise will revert by dup allowFill)
        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.salt = uint256(9001);

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);
        crdParams.salt = allowFill.salt;

        bytes memory payload2 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
        vm.expectRevert("PermanentStorage: transaction seen before");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload2);
    }

    function testCannotFillByTraderWithAlteredTakerTokenAmount() public {
        // Replace takerTokenAmount in traderParams without corresponded signature
        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerTokenAmount = DEFAULT_TRADER_PARAMS.takerTokenAmount.mul(2);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = traderParams.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
        vm.expectRevert("LimitOrder: Fill is not signed by taker");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithAlteredRecipient() public {
        // Replace recipient in traderParams without corresponded signature
        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.recipient = coordinator;
        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
        vm.expectRevert("LimitOrder: Fill is not signed by taker");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithExpiredAllowFill() public {
        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.expiry = uint64(block.timestamp - 1);

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);
        crdParams.expiry = allowFill.expiry;

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
        vm.expectRevert("LimitOrder: Fill permission is expired");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithAlteredOrderHash() public {
        // Replace orderHash in allowFill
        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = bytes32(0);

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
        vm.expectRevert("LimitOrder: AllowFill is not signed by coordinator");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithAlteredExecutor() public {
        // Set the executor to maker (not pionex)
        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.executor = maker;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        // Fill order using pionex (not executor)
        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
        vm.expectRevert("LimitOrder: AllowFill is not signed by coordinator");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithAlteredFillAmount() public {
        // Change fill amount in allow fill
        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = DEFAULT_ALLOW_FILL.fillAmount.div(2);

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
        vm.expectRevert("LimitOrder: AllowFill is not signed by coordinator");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithAllowFillNotSignedByCoordinator() public {
        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        // Sign allow fill using pionex's private key
        crdParams.sig = _signAllowFill(pionexPrivateKey, DEFAULT_ALLOW_FILL, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
        vm.expectRevert("LimitOrder: AllowFill is not signed by coordinator");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithReplayedAllowFill() public {
        // Fill with default allow fill
        bytes memory payload1 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload1);

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.takerSalt = uint256(8001);

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload2 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
        vm.expectRevert("PermanentStorage: allow fill seen before");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload2);
    }

    function testCannotFillByZeroTrader() public {
        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.recipient = address(0);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
        vm.expectRevert("LimitOrder: recipient can not be zero address");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotFillByTraderWithWorseTakerMakerTokenRatio() public {
        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // Increase maker token amount so the takerToken/makerToken ratio is worse than order's takerToken/makerToken ratio
        fill.makerTokenAmount = DEFAULT_FILL.makerTokenAmount.add(1);

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.makerTokenAmount = fill.makerTokenAmount;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
        vm.expectRevert("LimitOrder: taker/maker token ratio not good enough");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testFullyFillByTrader() public {
        BalanceSnapshot.Snapshot memory pionexTakerAsset = BalanceSnapshot.take(pionex, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory fcMakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory fcTakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.takerToken));

        // makerFeeFactor : 10%
        vm.startPrank(owner, owner);
        pionexContract.setFactors(1000);
        vm.warp(block.timestamp + pionexContract.factorActivateDelay());
        pionexContract.activateFactors();
        vm.stopPrank();

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.gasFeeFactor = 50; // gasFeeFactor: 0.5%
        traderParams.pionexStrategyFeeFactor = 250; // pionexStrategyFeeFactor: 2.5%
        traderParams.takerSig = _signFill(pionexPrivateKey, DEFAULT_FILL, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilledByTrader(
            DEFAULT_ORDER_HASH,
            DEFAULT_ORDER.maker,
            pionex,
            getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), PionexContractLibEIP712._getAllowFillStructHash(DEFAULT_ALLOW_FILL)),
            DEFAULT_TRADER_PARAMS.recipient,
            IPionexContract.FillReceipt(
                address(DEFAULT_ORDER.makerToken),
                address(DEFAULT_ORDER.takerToken),
                DEFAULT_ORDER.makerTokenAmount,
                DEFAULT_ORDER.takerTokenAmount,
                0, // remainingAmount should be zero after order fully filled
                DEFAULT_ORDER.takerTokenAmount.mul(10).div(100), // tokenlonFee = 10% takerTokenAmount
                DEFAULT_ORDER.takerTokenAmount.mul(3).div(100) // pionexStrategyFee = 0.5% + 2.5% = 3% takerTokenAmount
            )
        );
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);

        pionexTakerAsset.assertChange(-int256(DEFAULT_ORDER.takerTokenAmount.mul(97).div(100))); // 3% fee is deducted from takerTokenAmount directly
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.makerTokenAmount));
        makerTakerAsset.assertChange(int256(DEFAULT_ORDER.takerTokenAmount.mul(87).div(100)));
        makerMakerAsset.assertChange(-int256(DEFAULT_ORDER.makerTokenAmount));
        fcMakerAsset.assertChange(0);
        fcTakerAsset.assertChange(int256(DEFAULT_ORDER.takerTokenAmount.mul(10).div(100)));
    }

    function testFullyFillByTraderWithBetterTakerMakerTokenRatio() public {
        BalanceSnapshot.Snapshot memory pionexTakerAsset = BalanceSnapshot.take(pionex, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory fcMakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory fcTakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.takerToken));

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // Increase taker token amount so the takerToken/makerToken ratio is better than order's takerToken/makerToken ratio
        fill.takerTokenAmount = DEFAULT_FILL.takerTokenAmount.mul(11).div(10); // 10% more

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerTokenAmount = fill.takerTokenAmount;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = traderParams.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
        vm.expectEmit(true, true, true, true);
        emit LimitOrderFilledByTrader(
            DEFAULT_ORDER_HASH,
            DEFAULT_ORDER.maker,
            pionex,
            getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), PionexContractLibEIP712._getAllowFillStructHash(allowFill)),
            traderParams.recipient,
            IPionexContract.FillReceipt(
                address(DEFAULT_ORDER.makerToken),
                address(DEFAULT_ORDER.takerToken),
                DEFAULT_ORDER.makerTokenAmount,
                fill.takerTokenAmount,
                0, // remainingAmount should be zero after order fully filled
                0,
                0
            )
        );
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);

        pionexTakerAsset.assertChange(-int256(fill.takerTokenAmount));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.makerTokenAmount));
        makerTakerAsset.assertChange(int256(fill.takerTokenAmount)); // 10% more
        makerMakerAsset.assertChange(-int256(DEFAULT_ORDER.makerTokenAmount));
        fcMakerAsset.assertChange(0);
        fcTakerAsset.assertChange(0);
    }

    function testFullyFillByContractWalletTrader() public {
        // Contract mockERC1271Wallet as taker which always return valid ERC-1271 magic value no matter what.
        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.taker = address(mockERC1271Wallet);

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.taker = address(mockERC1271Wallet);
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.WalletBytes32);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.executor = address(mockERC1271Wallet);

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testFillBySpecificTaker() public {
        PionexContractLibEIP712.Order memory order = DEFAULT_ORDER;
        // order specify taker address
        order.taker = pionex;
        bytes32 orderHash = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), PionexContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrder(makerPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(order, orderMakerSig, traderParams, crdParams);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testFillBySpecificTakerWithOldEIP712Method() public {
        PionexContractLibEIP712.Order memory order = DEFAULT_ORDER;
        // order specify taker address
        order.taker = pionex;
        bytes32 orderHash = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), PionexContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrderWithOldEIP712Method(makerPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.takerSig = _signFillWithOldEIP712Method(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFillWithOldEIP712Method(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(order, orderMakerSig, traderParams, crdParams);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testOverFillByTrader() public {
        BalanceSnapshot.Snapshot memory pionexTakerAsset = BalanceSnapshot.take(pionex, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.makerToken));

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // set the fill amount to 2x of order quota
        fill.makerTokenAmount = DEFAULT_ORDER.makerTokenAmount.mul(2);
        fill.takerTokenAmount = DEFAULT_ORDER.takerTokenAmount.mul(2);

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.makerTokenAmount = fill.makerTokenAmount;
        traderParams.takerTokenAmount = fill.takerTokenAmount;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = fill.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);

        // Balance change should be bound by order amount (not affected by 2x fill amount)
        pionexTakerAsset.assertChange(-int256(DEFAULT_ORDER.takerTokenAmount));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.makerTokenAmount));
        makerTakerAsset.assertChange(int256(DEFAULT_ORDER.takerTokenAmount));
        makerMakerAsset.assertChange(-int256(DEFAULT_ORDER.makerTokenAmount));
    }

    function testOverFillByTraderWithBetterTakerMakerTokenRatio() public {
        BalanceSnapshot.Snapshot memory pionexTakerAsset = BalanceSnapshot.take(pionex, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.makerToken));

        PionexContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // set the fill amount to 2x of order quota
        fill.makerTokenAmount = DEFAULT_ORDER.makerTokenAmount.mul(2);
        fill.takerTokenAmount = DEFAULT_ORDER.takerTokenAmount.mul(2).mul(11).div(10); // 10% more

        IPionexContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.makerTokenAmount = fill.makerTokenAmount;
        traderParams.takerTokenAmount = fill.takerTokenAmount;
        traderParams.takerSig = _signFill(pionexPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = fill.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);

        // Balance change should be bound by order amount (not affected by 2x fill amount)
        pionexTakerAsset.assertChange(-int256(DEFAULT_ORDER.takerTokenAmount.mul(11).div(10))); // 10% more
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.makerTokenAmount));
        makerTakerAsset.assertChange(int256(DEFAULT_ORDER.takerTokenAmount.mul(11).div(10))); // 10% more
        makerMakerAsset.assertChange(-int256(DEFAULT_ORDER.makerTokenAmount));
    }

    function testFillByTraderMultipleTimes() public {
        BalanceSnapshot.Snapshot memory pionexTakerAsset = BalanceSnapshot.take(pionex, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.makerToken));

        // First fill amount : 9 USDT
        PionexContractLibEIP712.Fill memory fill1 = DEFAULT_FILL;
        fill1.makerTokenAmount = 10 * 1e18;
        fill1.takerTokenAmount = 9 * 1e6;
        IPionexContract.TraderParams memory traderParams1 = DEFAULT_TRADER_PARAMS;
        traderParams1.makerTokenAmount = fill1.makerTokenAmount;
        traderParams1.takerTokenAmount = fill1.takerTokenAmount;
        traderParams1.takerSig = _signFill(pionexPrivateKey, fill1, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill1 = DEFAULT_ALLOW_FILL;
        allowFill1.fillAmount = fill1.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams1 = DEFAULT_CRD_PARAMS;
        crdParams1.sig = _signAllowFill(coordinatorPrivateKey, allowFill1, SignatureValidator.SignatureType.EIP712);

        bytes memory payload1 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams1, crdParams1);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload1);

        // Second fill amount : 36 USDT
        PionexContractLibEIP712.Fill memory fill2 = DEFAULT_FILL;
        fill2.makerTokenAmount = 40 * 1e18;
        fill2.takerTokenAmount = 36 * 1e6;

        IPionexContract.TraderParams memory traderParams2 = DEFAULT_TRADER_PARAMS;
        traderParams2.makerTokenAmount = fill2.makerTokenAmount;
        traderParams2.takerTokenAmount = fill2.takerTokenAmount;
        traderParams2.takerSig = _signFill(pionexPrivateKey, fill2, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill2 = DEFAULT_ALLOW_FILL;
        allowFill2.fillAmount = fill2.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams2 = DEFAULT_CRD_PARAMS;
        crdParams2.sig = _signAllowFill(coordinatorPrivateKey, allowFill2, SignatureValidator.SignatureType.EIP712);

        bytes memory payload2 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams2, crdParams2);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload2);

        // Half of the order filled after 2 txs
        pionexTakerAsset.assertChange(-int256(DEFAULT_ORDER.takerTokenAmount.div(2)));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.makerTokenAmount.div(2)));
        makerTakerAsset.assertChange(int256(DEFAULT_ORDER.takerTokenAmount.div(2)));
        makerMakerAsset.assertChange(-int256(DEFAULT_ORDER.makerTokenAmount.div(2)));
    }

    function testFillByTraderMultipleTimesWithBetterTakerMakerTokenRatio() public {
        BalanceSnapshot.Snapshot memory pionexTakerAsset = BalanceSnapshot.take(pionex, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.makerToken));
        BalanceSnapshot.Snapshot memory makerTakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.takerToken));
        BalanceSnapshot.Snapshot memory makerMakerAsset = BalanceSnapshot.take(maker, address(DEFAULT_ORDER.makerToken));

        // First fill amount : 9 USDT and same takerToken/makerToken ratio
        PionexContractLibEIP712.Fill memory fill1 = DEFAULT_FILL;
        fill1.makerTokenAmount = 10 * 1e18;
        fill1.takerTokenAmount = 9 * 1e6;
        IPionexContract.TraderParams memory traderParams1 = DEFAULT_TRADER_PARAMS;
        traderParams1.makerTokenAmount = fill1.makerTokenAmount;
        traderParams1.takerTokenAmount = fill1.takerTokenAmount;
        traderParams1.takerSig = _signFill(pionexPrivateKey, fill1, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill1 = DEFAULT_ALLOW_FILL;
        allowFill1.fillAmount = fill1.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams1 = DEFAULT_CRD_PARAMS;
        crdParams1.sig = _signAllowFill(coordinatorPrivateKey, allowFill1, SignatureValidator.SignatureType.EIP712);

        bytes memory payload1 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams1, crdParams1);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload1);

        // Second fill amount : 36 USDT and better takerToken/makerToken ratio
        PionexContractLibEIP712.Fill memory fill2 = DEFAULT_FILL;
        fill2.makerTokenAmount = 40 * 1e18;
        fill2.takerTokenAmount = uint256(36 * 1e6).mul(11).div(10); // 10% more

        IPionexContract.TraderParams memory traderParams2 = DEFAULT_TRADER_PARAMS;
        traderParams2.makerTokenAmount = fill2.makerTokenAmount;
        traderParams2.takerTokenAmount = fill2.takerTokenAmount;
        traderParams2.takerSig = _signFill(pionexPrivateKey, fill2, SignatureValidator.SignatureType.EIP712);

        PionexContractLibEIP712.AllowFill memory allowFill2 = DEFAULT_ALLOW_FILL;
        allowFill2.fillAmount = fill2.takerTokenAmount;

        IPionexContract.CoordinatorParams memory crdParams2 = DEFAULT_CRD_PARAMS;
        crdParams2.sig = _signAllowFill(coordinatorPrivateKey, allowFill2, SignatureValidator.SignatureType.EIP712);

        bytes memory payload2 = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams2, crdParams2);
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload2);

        // Half of the order filled after 2 txs
        pionexTakerAsset.assertChange(-int256(fill1.takerTokenAmount.add(fill2.takerTokenAmount)));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.makerTokenAmount.div(2)));
        makerTakerAsset.assertChange(int256(fill1.takerTokenAmount.add(fill2.takerTokenAmount)));
        makerMakerAsset.assertChange(-int256(DEFAULT_ORDER.makerTokenAmount.div(2)));
    }

    /*********************************
     *        cancelLimitOrder       *
     *********************************/

    function testCannotFillCanceledOrder() public {
        PionexContractLibEIP712.Order memory zeroOrder = DEFAULT_ORDER;
        zeroOrder.takerTokenAmount = 0;

        bytes memory cancelPayload = _genCancelLimitOrderPayload(
            DEFAULT_ORDER,
            _signOrder(makerPrivateKey, zeroOrder, SignatureValidator.SignatureType.EIP712)
        );
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(cancelPayload);

        bytes memory payload = _genFillByTraderPayload(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
        vm.expectRevert("LimitOrder: Order is cancelled");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotCancelIfNotMaker() public {
        PionexContractLibEIP712.Order memory zeroOrder = DEFAULT_ORDER;
        zeroOrder.takerTokenAmount = 0;

        bytes memory cancelPayload = _genCancelLimitOrderPayload(
            DEFAULT_ORDER,
            _signOrder(pionexPrivateKey, zeroOrder, SignatureValidator.SignatureType.EIP712)
        );
        vm.expectRevert("LimitOrder: Cancel request is not signed by maker");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(cancelPayload);
    }

    function testCannotCancelExpiredOrder() public {
        PionexContractLibEIP712.Order memory expiredOrder = DEFAULT_ORDER;
        expiredOrder.expiry = 0;

        bytes memory payload = _genCancelLimitOrderPayload(expiredOrder, _signOrder(pionexPrivateKey, expiredOrder, SignatureValidator.SignatureType.EIP712));
        vm.expectRevert("LimitOrder: Order is expired");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function testCannotCancelTwice() public {
        PionexContractLibEIP712.Order memory zeroOrder = DEFAULT_ORDER;
        zeroOrder.takerTokenAmount = 0;

        bytes memory payload = _genCancelLimitOrderPayload(DEFAULT_ORDER, _signOrder(makerPrivateKey, zeroOrder, SignatureValidator.SignatureType.EIP712));
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
        vm.expectRevert("LimitOrder: Order is cancelled already");
        vm.prank(pionex, pionex); // Only EOA
        userProxy.toLimitOrder(payload);
    }

    function _signOrderEIP712(
        address limitOrderAddr,
        uint256 privateKey,
        PionexContractLibEIP712.Order memory order
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = PionexContractLibEIP712._getOrderStructHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(limitOrderAddr), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _signFillEIP712(
        address limitOrderAddr,
        uint256 privateKey,
        PionexContractLibEIP712.Fill memory fill
    ) internal returns (bytes memory sig) {
        bytes32 fillHash = PionexContractLibEIP712._getFillStructHash(fill);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(limitOrderAddr), fillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _signAllowFillEIP712(
        address limitOrderAddr,
        uint256 privateKey,
        PionexContractLibEIP712.AllowFill memory allowFill
    ) internal returns (bytes memory sig) {
        bytes32 allowFillHash = PionexContractLibEIP712._getAllowFillStructHash(allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(limitOrderAddr), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function _signOrder(
        uint256 privateKey,
        PionexContractLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = PionexContractLibEIP712._getOrderStructHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), orderHash);

        if (sigType == SignatureValidator.SignatureType.EIP712) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
            sig = abi.encodePacked(r, s, v, uint8(sigType));
        } else if (sigType == SignatureValidator.SignatureType.Wallet) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toEthSignedMessageHash(EIP712SignDigest));
            sig = abi.encodePacked(v, r, s, uint8(sigType));
        } else {
            revert("Invalid signature type");
        }
    }

    function _signOrderWithOldEIP712Method(
        uint256 privateKey,
        PionexContractLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = PionexContractLibEIP712._getOrderStructHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), orderHash);
        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }

    function _signFill(
        uint256 privateKey,
        PionexContractLibEIP712.Fill memory fill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 fillHash = PionexContractLibEIP712._getFillStructHash(fill);
        bytes32 EIP712SignDigest = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), fillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, uint8(sigType));
    }

    function _signFillWithOldEIP712Method(
        uint256 privateKey,
        PionexContractLibEIP712.Fill memory fill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 fillHash = PionexContractLibEIP712._getFillStructHash(fill);
        bytes32 EIP712SignDigest = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), fillHash);
        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }

    function _signAllowFill(
        uint256 privateKey,
        PionexContractLibEIP712.AllowFill memory allowFill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 allowFillHash = PionexContractLibEIP712._getAllowFillStructHash(allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, uint8(sigType));
    }

    function _signAllowFillWithOldEIP712Method(
        uint256 privateKey,
        PionexContractLibEIP712.AllowFill memory allowFill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 allowFillHash = PionexContractLibEIP712._getAllowFillStructHash(allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(pionexContract.EIP712_DOMAIN_SEPARATOR(), allowFillHash);
        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }

    function _genFillByTraderPayload(
        PionexContractLibEIP712.Order memory order,
        bytes memory orderMakerSig,
        IPionexContract.TraderParams memory params,
        IPionexContract.CoordinatorParams memory crdParams
    ) internal view returns (bytes memory payload) {
        return abi.encodeWithSelector(pionexContract.fillLimitOrderByTrader.selector, order, orderMakerSig, params, crdParams);
    }

    function _genCancelLimitOrderPayload(PionexContractLibEIP712.Order memory order, bytes memory cancelOrderMakerSig)
        internal
        view
        returns (bytes memory payload)
    {
        return abi.encodeWithSelector(pionexContract.cancelLimitOrder.selector, order, cancelOrderMakerSig);
    }
}
