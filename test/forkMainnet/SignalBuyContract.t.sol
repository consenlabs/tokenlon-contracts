// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "contracts/SignalBuyContract.sol";
import "contracts/interfaces/ISignalBuyContract.sol";
import "contracts/utils/SignatureValidator.sol";
import "contracts/utils/SignalBuyContractLibEIP712.sol";
import "contracts/utils/LibConstant.sol";

import "test/mocks/MockERC1271Wallet.sol";
import "test/utils/BalanceSnapshot.sol";
import "test/utils/BalanceUtil.sol";
import { computeMainnetEIP712DomainSeparator, getEIP712Hash } from "test/utils/Sig.sol";

contract SignalBuyContractTest is BalanceUtil {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    event SignalBuyFilledByTrader(
        bytes32 indexed orderHash,
        address indexed user,
        address indexed dealer,
        bytes32 allowFillHash,
        address recipient,
        ISignalBuyContract.FillReceipt fillReceipt
    );

    uint256 dealerPrivateKey = uint256(1);
    uint256 userPrivateKey = uint256(2);
    uint256 coordinatorPrivateKey = uint256(3);

    address dealer = vm.addr(dealerPrivateKey);
    address user = vm.addr(userPrivateKey);
    address coordinator = vm.addr(coordinatorPrivateKey);
    address owner = makeAddr("owner");
    address feeCollector = makeAddr("feeCollector");
    address receiver = makeAddr("receiver");
    MockERC1271Wallet mockERC1271Wallet = new MockERC1271Wallet(dealer);
    address[] wallet = [dealer, user, coordinator, address(mockERC1271Wallet)];
    address[] allowanceAddrs;

    address[] DEFAULT_AMM_PATH;
    SignalBuyContractLibEIP712.Order DEFAULT_ORDER;
    bytes32 DEFAULT_ORDER_HASH;
    bytes DEFAULT_ORDER_MAKER_SIG;
    SignalBuyContractLibEIP712.Fill DEFAULT_FILL;
    SignalBuyContractLibEIP712.AllowFill DEFAULT_ALLOW_FILL;
    uint16 DEFAULT_GAS_FEE_FACTOR = 0;
    uint16 DEFAULT_PIONEX_STRATEGY_FEE_FACTOR = 0;
    ISignalBuyContract.TraderParams DEFAULT_TRADER_PARAMS;
    ISignalBuyContract.CoordinatorParams DEFAULT_CRD_PARAMS;

    SignalBuyContract signalBuyContract;
    uint64 DEADLINE = uint64(block.timestamp + 2 days);
    uint256 FACTORSDEALY = 12 hours;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        signalBuyContract = new SignalBuyContract(owner, address(weth), coordinator, FACTORSDEALY, feeCollector);

        DEFAULT_AMM_PATH = [address(dai), address(usdt)];
        allowanceAddrs = DEFAULT_AMM_PATH;

        // Default params
        DEFAULT_ORDER = SignalBuyContractLibEIP712.Order(
            dai, // userToken
            usdt, // dealerToken
            100 * 1e18, // userTokenAmount
            90 * 1e6, // minDealerTokenAmount
            user, // user
            address(0), // dealer
            uint256(1001), // salt
            DEADLINE // expiry
        );
        DEFAULT_ORDER_HASH = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(DEFAULT_ORDER));
        DEFAULT_ORDER_MAKER_SIG = _signOrder(userPrivateKey, DEFAULT_ORDER, SignatureValidator.SignatureType.EIP712);
        DEFAULT_FILL = SignalBuyContractLibEIP712.Fill(
            DEFAULT_ORDER_HASH,
            dealer,
            receiver,
            DEFAULT_ORDER.userTokenAmount,
            DEFAULT_ORDER.minDealerTokenAmount,
            uint256(1002),
            DEADLINE
        );
        DEFAULT_TRADER_PARAMS = ISignalBuyContract.TraderParams(
            dealer, // dealer
            receiver, // recipient
            DEFAULT_FILL.userTokenAmount, // userTokenAmount
            DEFAULT_FILL.dealerTokenAmount, // dealerTokenAmount
            DEFAULT_GAS_FEE_FACTOR, // gas fee factor
            DEFAULT_PIONEX_STRATEGY_FEE_FACTOR, // dealer strategy fee factor
            DEFAULT_FILL.dealerSalt, // salt
            DEADLINE, // expiry
            _signFill(dealerPrivateKey, DEFAULT_FILL, SignatureValidator.SignatureType.EIP712) // dealerSig
        );
        DEFAULT_ALLOW_FILL = SignalBuyContractLibEIP712.AllowFill(
            DEFAULT_ORDER_HASH, // orderHash
            dealer, // executor
            DEFAULT_FILL.dealerTokenAmount, // fillAmount
            uint256(1003), // salt
            DEADLINE // expiry
        );
        DEFAULT_CRD_PARAMS = ISignalBuyContract.CoordinatorParams(
            _signAllowFill(coordinatorPrivateKey, DEFAULT_ALLOW_FILL, SignatureValidator.SignatureType.EIP712),
            DEFAULT_ALLOW_FILL.salt,
            DEFAULT_ALLOW_FILL.expiry
        );

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        tokens = [weth, usdt, dai];
        setEOABalanceAndApprove(dealer, tokens, 10000);
        setEOABalanceAndApprove(user, tokens, 10000);
        setEOABalanceAndApprove(address(mockERC1271Wallet), tokens, 10000);

        // Label addresses for easier debugging
        vm.label(dealer, "SignalBuy");
        vm.label(user, "User");
        vm.label(coordinator, "Coordinator");
        vm.label(receiver, "Receiver");
        vm.label(feeCollector, "FeeCollector");
        vm.label(address(this), "TestingContract");
        vm.label(address(signalBuyContract), "SignalBuyContract");
        vm.label(address(mockERC1271Wallet), "MockERC1271Wallet");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupSignalBuy() public {
        assertEq(signalBuyContract.owner(), owner);
        assertEq(signalBuyContract.coordinator(), coordinator);
        assertEq(address(signalBuyContract.weth()), address(weth));

        assertEq(uint256(signalBuyContract.tokenlonFeeFactor()), 0);
    }

    /*********************************
     *     Test: transferOwnership   *
     *********************************/

    function testCannotTransferOwnershipByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(dealer);
        signalBuyContract.nominateNewOwner(dealer);
    }

    function testCannotAcceptOwnershipIfNotNominated() public {
        vm.expectRevert("not nominated");
        vm.prank(dealer);
        signalBuyContract.acceptOwnership();
    }

    function testTransferOwnership() public {
        vm.prank(owner, owner);
        signalBuyContract.nominateNewOwner(dealer);
        vm.prank(dealer);
        signalBuyContract.acceptOwnership();
        assertEq(signalBuyContract.owner(), dealer);
    }

    /*********************************
     *     Test: upgradeCoordinator  *
     *********************************/

    function testCannotUpgradeCoordinatorByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(dealer);
        signalBuyContract.upgradeCoordinator(dealer);
    }

    function testCannotUpgradeCoordinatorToZeroAddr() public {
        vm.expectRevert("SignalBuyContract: coordinator can not be zero address");
        vm.prank(owner, owner);
        signalBuyContract.upgradeCoordinator(address(0));
    }

    function testUpgradeCoordinator() public {
        vm.prank(owner, owner);
        signalBuyContract.upgradeCoordinator(dealer);
        assertEq(address(signalBuyContract.coordinator()), dealer);
    }

    /*********************************
     *   Test: set/close allowance   *
     *********************************/

    function testCannotSetAllowanceByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(dealer);
        signalBuyContract.setAllowance(allowanceAddrs, address(receiver));
    }

    function testCannotCloseAllowanceByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(dealer);
        signalBuyContract.closeAllowance(allowanceAddrs, address(receiver));
    }

    function testSetAndCloseAllowance() public {
        // Set allowance
        vm.prank(owner, owner);
        signalBuyContract.setAllowance(allowanceAddrs, address(receiver));
        assertEq(usdt.allowance(address(signalBuyContract), address(receiver)), LibConstant.MAX_UINT);
        assertEq(dai.allowance(address(signalBuyContract), address(receiver)), LibConstant.MAX_UINT);

        // Close allowance
        vm.prank(owner, owner);
        signalBuyContract.closeAllowance(allowanceAddrs, address(receiver));
        assertEq(usdt.allowance(address(signalBuyContract), address(receiver)), 0);
        assertEq(dai.allowance(address(signalBuyContract), address(receiver)), 0);
    }

    /*********************************
     *        Test: depoitETH        *
     *********************************/

    function testCannotDepositETHByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(dealer);
        signalBuyContract.depositETH();
    }

    function testDepositETH() public {
        // Send ether to limit order contract
        uint256 amount = 1234 ether;
        deal(address(signalBuyContract), amount);
        vm.prank(owner, owner);
        signalBuyContract.depositETH();
        assertEq(weth.balanceOf(address(signalBuyContract)), amount);
    }

    /*********************************
     *        Test: setFactors       *
     *********************************/

    function testCannotSetFactorsIfLargerThanBpsMax() public {
        vm.expectRevert("SignalBuyContract: Invalid user fee factor");
        vm.prank(owner, owner);
        signalBuyContract.setFactors(LibConstant.BPS_MAX + 1);
    }

    function testSetFactors() public {
        vm.startPrank(owner, owner);
        signalBuyContract.setFactors(1);
        // fee factors should stay same before new ones activate
        assertEq(uint256(signalBuyContract.tokenlonFeeFactor()), 0);
        vm.warp(block.timestamp + signalBuyContract.factorActivateDelay());

        // fee factors should be updated now
        signalBuyContract.activateFactors();
        vm.stopPrank();
        assertEq(uint256(signalBuyContract.tokenlonFeeFactor()), 1);
    }

    /*********************************
     *     Test: setFeeCollector     *
     *********************************/

    function testCannotSetFeeCollectorByNotOwner() public {
        vm.expectRevert("not owner");
        vm.prank(dealer);
        signalBuyContract.setFeeCollector(feeCollector);
    }

    function testCannotSetFeeCollectorToZeroAddr() public {
        vm.expectRevert("SignalBuyContract: fee collector can not be zero address");
        vm.prank(owner, owner);
        signalBuyContract.setFeeCollector(address(0));
    }

    function testSetFeeCollector() public {
        vm.prank(owner, owner);
        signalBuyContract.setFeeCollector(dealer);
        assertEq(address(signalBuyContract.feeCollector()), dealer);
    }

    /*********************************
     *  Test: fillSignalBuy *
     *********************************/

    function testCannotFillFilledOrderByTrader() public {
        // Fullly fill the default order first
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);

        // Try to fill the default order, should fail
        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.dealerSalt = uint256(8001);

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);
        traderParams.salt = fill.dealerSalt;

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.salt = uint256(8002);

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);
        crdParams.salt = allowFill.salt;

        vm.expectRevert("SignalBuyContract: Order is filled");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
    }

    function testCannotFillExpiredOrderByTrader() public {
        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        order.expiry = uint64(block.timestamp - 1);

        bytes32 orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrder(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Order is expired");
        signalBuyContract.fillSignalBuy(order, orderMakerSig, traderParams, crdParams);
    }

    function testCannotFillByTraderWithWrongMakerSig() public {
        bytes memory wrongMakerSig = _signOrder(dealerPrivateKey, DEFAULT_ORDER, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Order is not signed by user");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, wrongMakerSig, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
    }

    function testCannotFillByTraderWithWrongTakerSig() public {
        ISignalBuyContract.TraderParams memory wrongTraderParams = DEFAULT_TRADER_PARAMS;
        wrongTraderParams.dealerSig = _signFill(userPrivateKey, DEFAULT_FILL, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Fill is not signed by dealer");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, wrongTraderParams, DEFAULT_CRD_PARAMS);
    }

    function testCannotFillByTraderWithTakerOtherThanOrderSpecified() public {
        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        // order specify dealer address
        order.dealer = coordinator;
        bytes32 orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrder(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        // dealer try to fill this order
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Order cannot be filled by this dealer");
        signalBuyContract.fillSignalBuy(order, orderMakerSig, traderParams, crdParams);
    }

    function testCannotFillByTraderWithExpiredFill() public {
        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.expiry = uint64(block.timestamp - 1);

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);
        traderParams.expiry = fill.expiry;

        vm.expectRevert("SignalBuyContract: Fill request is expired");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
    }

    function testCannotReplayFill() public {
        // Fill with DEFAULT_FILL
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);

        // Try to fill with same fill request with differnt allowFill (otherwise will revert by dup allowFill)
        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.salt = uint256(9001);

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);
        crdParams.salt = allowFill.salt;

        vm.expectRevert("SignalBuyContract: Fill seen before");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
    }

    function testCannotFillByTraderWithAlteredTakerTokenAmount() public {
        // Replace dealerTokenAmount in traderParams without corresponded signature
        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerTokenAmount = DEFAULT_TRADER_PARAMS.dealerTokenAmount.mul(2);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Fill is not signed by dealer");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
    }

    function testCannotFillByTraderWithAlteredRecipient() public {
        // Replace recipient in traderParams without corresponded signature
        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.recipient = coordinator;
        vm.expectRevert("SignalBuyContract: Fill is not signed by dealer");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
    }

    function testCannotFillByTraderWithExpiredAllowFill() public {
        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.expiry = uint64(block.timestamp - 1);

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);
        crdParams.expiry = allowFill.expiry;

        vm.expectRevert("SignalBuyContract: Fill permission is expired");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
    }

    function testCannotFillByTraderWithAlteredOrderHash() public {
        // Replace orderHash in allowFill
        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = bytes32(0);

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: AllowFill is not signed by coordinator");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
    }

    function testCannotFillByTraderWithAlteredExecutor() public {
        // Set the executor to user (not dealer)
        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.executor = user;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        // Fill order using dealer (not executor)
        vm.expectRevert("SignalBuyContract: AllowFill is not signed by coordinator");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
    }

    function testCannotFillByTraderWithAlteredFillAmount() public {
        // Change fill amount in allow fill
        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = DEFAULT_ALLOW_FILL.fillAmount.div(2);

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: AllowFill is not signed by coordinator");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
    }

    function testCannotFillByTraderWithAllowFillNotSignedByCoordinator() public {
        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        // Sign allow fill using dealer's private key
        crdParams.sig = _signAllowFill(dealerPrivateKey, DEFAULT_ALLOW_FILL, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: AllowFill is not signed by coordinator");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, crdParams);
    }

    function testCannotFillByTraderWithReplayedAllowFill() public {
        // Fill with default allow fill
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.dealerSalt = uint256(8001);

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Fill seen before");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
    }

    function testCannotFillByZeroTrader() public {
        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.recipient = address(0);

        vm.expectRevert("SignalBuyContract: recipient can not be zero address");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
    }

    function testCannotFillByTraderWithWorseTakerMakerTokenRatio() public {
        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // Increase user token amount so the dealerToken/userToken ratio is worse than order's dealerToken/userToken ratio
        fill.userTokenAmount = DEFAULT_FILL.userTokenAmount.add(1);

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.userTokenAmount = fill.userTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: dealer token amount not enough");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
    }

    function testCannotFullyFillByTraderWithWorseTakerTokenAmountDueToFee() public {
        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.gasFeeFactor = 50; // gasFeeFactor: 0.5%
        traderParams.dealerStrategyFeeFactor = 250; // dealerStrategyFeeFactor: 2.5%
        traderParams.dealerSig = _signFill(dealerPrivateKey, DEFAULT_FILL, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: dealer token amount not enough");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, DEFAULT_CRD_PARAMS);
    }

    function testFullyFillByTraderWithNoFee() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcMakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcTakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.dealerToken));

        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            DEFAULT_ORDER_HASH,
            DEFAULT_ORDER.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(DEFAULT_ALLOW_FILL)),
            DEFAULT_TRADER_PARAMS.recipient,
            ISignalBuyContract.FillReceipt(
                address(DEFAULT_ORDER.userToken),
                address(DEFAULT_ORDER.dealerToken),
                DEFAULT_ORDER.userTokenAmount,
                DEFAULT_ORDER.minDealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                0, // tokenlonFee = 0
                0 // dealerStrategyFee = 0
            )
        );
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);

        dealerTakerAsset.assertChange(-int256(DEFAULT_ORDER.minDealerTokenAmount));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount));
        userTakerAsset.assertChange(int256(DEFAULT_ORDER.minDealerTokenAmount));
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount));
        fcMakerAsset.assertChange(0);
        fcTakerAsset.assertChange(0);
    }

    function testFullyFillByTraderWithAddedTokenlonFee() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcMakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcTakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.dealerToken));

        // tokenlonFeeFactor : 10%
        vm.startPrank(owner, owner);
        signalBuyContract.setFactors(1000);
        vm.warp(block.timestamp + signalBuyContract.factorActivateDelay());
        signalBuyContract.activateFactors();
        vm.stopPrank();

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // Increase dealer token amount so the dealerToken/userToken ratio is better than order's dealerToken/userToken ratio
        // to account for tokenlon fee
        fill.dealerTokenAmount = DEFAULT_FILL.dealerTokenAmount.mul(115).div(100); // 15% more

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            DEFAULT_ORDER_HASH,
            DEFAULT_ORDER.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill)),
            DEFAULT_TRADER_PARAMS.recipient,
            ISignalBuyContract.FillReceipt(
                address(DEFAULT_ORDER.userToken),
                address(DEFAULT_ORDER.dealerToken),
                DEFAULT_ORDER.userTokenAmount,
                traderParams.dealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                traderParams.dealerTokenAmount.div(10), // tokenlonFee = 10% dealerTokenAmount
                0 // dealerStrategyFee = 0
            )
        );
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);

        dealerTakerAsset.assertChange(-int256(traderParams.dealerTokenAmount));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount));
        userTakerAsset.assertChange(int256(traderParams.dealerTokenAmount.mul(9).div(10))); // 10% fee for Tokenlon
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount));
        fcMakerAsset.assertChange(0);
        fcTakerAsset.assertChange(int256(traderParams.dealerTokenAmount.div(10)));
    }

    function testFullyFillByTraderWithAddedGasFeeAndStrategyFee() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcMakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcTakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.dealerToken));

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // Increase dealer token amount so the dealerToken/userToken ratio is better than order's dealerToken/userToken ratio
        // to account for gas fee and dealer strategy fee
        fill.dealerTokenAmount = DEFAULT_FILL.dealerTokenAmount.mul(11).div(10); // 10% more

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.gasFeeFactor = 50; // gasFeeFactor: 0.5%
        traderParams.dealerStrategyFeeFactor = 250; // dealerStrategyFeeFactor: 2.5%
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            DEFAULT_ORDER_HASH,
            DEFAULT_ORDER.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill)),
            DEFAULT_TRADER_PARAMS.recipient,
            ISignalBuyContract.FillReceipt(
                address(DEFAULT_ORDER.userToken),
                address(DEFAULT_ORDER.dealerToken),
                DEFAULT_ORDER.userTokenAmount,
                traderParams.dealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                0, // tokenlonFee = 0
                traderParams.dealerTokenAmount.mul(3).div(100) // dealerStrategyFee = 0.5% + 2.5% = 3% dealerTokenAmount
            )
        );
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);

        dealerTakerAsset.assertChange(-int256(traderParams.dealerTokenAmount.mul(97).div(100))); // 3% fee for SignalBuy is deducted from dealerTokenAmount directly
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount));
        userTakerAsset.assertChange(int256(traderParams.dealerTokenAmount.mul(97).div(100))); // 3% fee for SignalBuy
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount));
        fcMakerAsset.assertChange(0);
        fcTakerAsset.assertChange(0);
    }

    function testFullyFillByTraderWithBetterTakerMakerTokenRatio() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcMakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory fcTakerAsset = BalanceSnapshot.take(feeCollector, address(DEFAULT_ORDER.dealerToken));

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // Increase dealer token amount so the dealerToken/userToken ratio is better than order's dealerToken/userToken ratio
        fill.dealerTokenAmount = DEFAULT_FILL.dealerTokenAmount.mul(11).div(10); // 10% more

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            DEFAULT_ORDER_HASH,
            DEFAULT_ORDER.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill)),
            traderParams.recipient,
            ISignalBuyContract.FillReceipt(
                address(DEFAULT_ORDER.userToken),
                address(DEFAULT_ORDER.dealerToken),
                DEFAULT_ORDER.userTokenAmount,
                fill.dealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                0,
                0
            )
        );
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);

        dealerTakerAsset.assertChange(-int256(fill.dealerTokenAmount));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount));
        userTakerAsset.assertChange(int256(fill.dealerTokenAmount)); // 10% more
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount));
        fcMakerAsset.assertChange(0);
        fcTakerAsset.assertChange(0);
    }

    function testFullyFillByContractWalletTrader() public {
        // Contract mockERC1271Wallet as dealer which always return valid ERC-1271 magic value no matter what.
        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.dealer = address(mockERC1271Wallet);

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealer = address(mockERC1271Wallet);
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.WalletBytes32);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.executor = address(mockERC1271Wallet);

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);
    }

    function testFillBySpecificTaker() public {
        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        // order specify dealer address
        order.dealer = dealer;
        bytes32 orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrder(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(order, orderMakerSig, traderParams, crdParams);
    }

    function testFillBySpecificTakerWithOldEIP712Method() public {
        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        // order specify dealer address
        order.dealer = dealer;
        bytes32 orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        bytes memory orderMakerSig = _signOrderWithOldEIP712Method(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = orderHash;

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerSig = _signFillWithOldEIP712Method(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = orderHash;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFillWithOldEIP712Method(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(order, orderMakerSig, traderParams, crdParams);
    }

    function testOverFillByTrader() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // set the fill amount to 2x of order quota
        fill.userTokenAmount = DEFAULT_ORDER.userTokenAmount.mul(2);
        fill.dealerTokenAmount = DEFAULT_ORDER.minDealerTokenAmount.mul(2);

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.userTokenAmount = fill.userTokenAmount;
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = fill.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);

        // Balance change should be bound by order amount (not affected by 2x fill amount)
        dealerTakerAsset.assertChange(-int256(DEFAULT_ORDER.minDealerTokenAmount));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount));
        userTakerAsset.assertChange(int256(DEFAULT_ORDER.minDealerTokenAmount));
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount));
    }

    function testOverFillByTraderWithBetterTakerMakerTokenRatio() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        // set the fill amount to 2x of order quota
        fill.userTokenAmount = DEFAULT_ORDER.userTokenAmount.mul(2);
        fill.dealerTokenAmount = DEFAULT_ORDER.minDealerTokenAmount.mul(2).mul(11).div(10); // 10% more

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.userTokenAmount = fill.userTokenAmount;
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.fillAmount = fill.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams, crdParams);

        // Balance change should be bound by order amount (not affected by 2x fill amount)
        dealerTakerAsset.assertChange(-int256(DEFAULT_ORDER.minDealerTokenAmount.mul(11).div(10))); // 10% more
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount));
        userTakerAsset.assertChange(int256(DEFAULT_ORDER.minDealerTokenAmount.mul(11).div(10))); // 10% more
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount));
    }

    function testFillByTraderMultipleTimes() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));

        // First fill amount : 9 USDT
        SignalBuyContractLibEIP712.Fill memory fill1 = DEFAULT_FILL;
        fill1.userTokenAmount = 10 * 1e18;
        fill1.dealerTokenAmount = 9 * 1e6;
        ISignalBuyContract.TraderParams memory traderParams1 = DEFAULT_TRADER_PARAMS;
        traderParams1.userTokenAmount = fill1.userTokenAmount;
        traderParams1.dealerTokenAmount = fill1.dealerTokenAmount;
        traderParams1.dealerSig = _signFill(dealerPrivateKey, fill1, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill1 = DEFAULT_ALLOW_FILL;
        allowFill1.fillAmount = fill1.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams1 = DEFAULT_CRD_PARAMS;
        crdParams1.sig = _signAllowFill(coordinatorPrivateKey, allowFill1, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams1, crdParams1);

        // Second fill amount : 36 USDT
        SignalBuyContractLibEIP712.Fill memory fill2 = DEFAULT_FILL;
        fill2.userTokenAmount = 40 * 1e18;
        fill2.dealerTokenAmount = 36 * 1e6;

        ISignalBuyContract.TraderParams memory traderParams2 = DEFAULT_TRADER_PARAMS;
        traderParams2.userTokenAmount = fill2.userTokenAmount;
        traderParams2.dealerTokenAmount = fill2.dealerTokenAmount;
        traderParams2.dealerSig = _signFill(dealerPrivateKey, fill2, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill2 = DEFAULT_ALLOW_FILL;
        allowFill2.fillAmount = fill2.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams2 = DEFAULT_CRD_PARAMS;
        crdParams2.sig = _signAllowFill(coordinatorPrivateKey, allowFill2, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams2, crdParams2);

        // Half of the order filled after 2 txs
        dealerTakerAsset.assertChange(-int256(DEFAULT_ORDER.minDealerTokenAmount.div(2)));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount.div(2)));
        userTakerAsset.assertChange(int256(DEFAULT_ORDER.minDealerTokenAmount.div(2)));
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount.div(2)));
    }

    function testFillByTraderMultipleTimesWithBetterTakerMakerTokenRatio() public {
        BalanceSnapshot.Snapshot memory dealerTakerAsset = BalanceSnapshot.take(dealer, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory receiverMakerAsset = BalanceSnapshot.take(receiver, address(DEFAULT_ORDER.userToken));
        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.dealerToken));
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, address(DEFAULT_ORDER.userToken));

        // First fill amount : 9 USDT and same dealerToken/userToken ratio
        SignalBuyContractLibEIP712.Fill memory fill1 = DEFAULT_FILL;
        fill1.userTokenAmount = 10 * 1e18;
        fill1.dealerTokenAmount = 9 * 1e6;
        ISignalBuyContract.TraderParams memory traderParams1 = DEFAULT_TRADER_PARAMS;
        traderParams1.userTokenAmount = fill1.userTokenAmount;
        traderParams1.dealerTokenAmount = fill1.dealerTokenAmount;
        traderParams1.dealerSig = _signFill(dealerPrivateKey, fill1, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill1 = DEFAULT_ALLOW_FILL;
        allowFill1.fillAmount = fill1.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams1 = DEFAULT_CRD_PARAMS;
        crdParams1.sig = _signAllowFill(coordinatorPrivateKey, allowFill1, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams1, crdParams1);

        // Second fill amount : 36 USDT and better dealerToken/userToken ratio
        SignalBuyContractLibEIP712.Fill memory fill2 = DEFAULT_FILL;
        fill2.userTokenAmount = 40 * 1e18;
        fill2.dealerTokenAmount = uint256(36 * 1e6).mul(11).div(10); // 10% more

        ISignalBuyContract.TraderParams memory traderParams2 = DEFAULT_TRADER_PARAMS;
        traderParams2.userTokenAmount = fill2.userTokenAmount;
        traderParams2.dealerTokenAmount = fill2.dealerTokenAmount;
        traderParams2.dealerSig = _signFill(dealerPrivateKey, fill2, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill2 = DEFAULT_ALLOW_FILL;
        allowFill2.fillAmount = fill2.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams2 = DEFAULT_CRD_PARAMS;
        crdParams2.sig = _signAllowFill(coordinatorPrivateKey, allowFill2, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, traderParams2, crdParams2);

        // Half of the order filled after 2 txs
        dealerTakerAsset.assertChange(-int256(fill1.dealerTokenAmount.add(fill2.dealerTokenAmount)));
        receiverMakerAsset.assertChange(int256(DEFAULT_ORDER.userTokenAmount.div(2)));
        userTakerAsset.assertChange(int256(fill1.dealerTokenAmount.add(fill2.dealerTokenAmount)));
        userMakerAsset.assertChange(-int256(DEFAULT_ORDER.userTokenAmount.div(2)));
    }

    /*********************************
     *      ETH/WETH settlement      *
     *********************************/

    struct ETHandWETHAssetSnapshot {
        BalanceSnapshot.Snapshot dealerETHAsset;
        BalanceSnapshot.Snapshot dealerWETHAsset;
        BalanceSnapshot.Snapshot userETHAsset;
        BalanceSnapshot.Snapshot userWETHAsset;
    }
    ETHandWETHAssetSnapshot assetSnapshots;

    function testSettlementETHToETHWithNoFee() public {
        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        order.dealerToken = IERC20(LibConstant.ETH_ADDRESS);
        order.minDealerTokenAmount = 1e18;
        bytes memory orderMakerSig = _signOrder(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        fill.dealerTokenAmount = order.minDealerTokenAmount;

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        assetSnapshots.dealerETHAsset = BalanceSnapshot.take(dealer, LibConstant.ETH_ADDRESS);
        assetSnapshots.dealerWETHAsset = BalanceSnapshot.take(dealer, address(weth));
        assetSnapshots.userETHAsset = BalanceSnapshot.take(user, LibConstant.ETH_ADDRESS);
        assetSnapshots.userWETHAsset = BalanceSnapshot.take(user, address(weth));

        // Case 1: Tx failed due to mismatch msg.value
        vm.expectRevert("SignalBuyContract: mismatch dealer token (ETH) amount");
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy{ value: fill.dealerTokenAmount - 1 }(order, orderMakerSig, traderParams, crdParams);

        // Case 2: Tx succeeded
        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order)),
            order.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill)),
            DEFAULT_TRADER_PARAMS.recipient,
            ISignalBuyContract.FillReceipt(
                address(order.userToken),
                address(order.dealerToken),
                order.userTokenAmount,
                order.minDealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                0, // tokenlonFee = 0
                0 // dealerStrategyFee = 0
            )
        );
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy{ value: fill.dealerTokenAmount }(order, orderMakerSig, traderParams, crdParams);

        assetSnapshots.dealerETHAsset.assertChange(-int256(order.minDealerTokenAmount));
        assetSnapshots.dealerWETHAsset.assertChange(0);
        assetSnapshots.userETHAsset.assertChange(int256(order.minDealerTokenAmount));
        assetSnapshots.userWETHAsset.assertChange(0);
    }

    function testSettlementWETHToWETHWithNoFee() public {
        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        order.dealerToken = weth;
        order.minDealerTokenAmount = 1e18;
        bytes memory orderMakerSig = _signOrder(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        fill.dealerTokenAmount = order.minDealerTokenAmount;

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        assetSnapshots.dealerETHAsset = BalanceSnapshot.take(dealer, LibConstant.ETH_ADDRESS);
        assetSnapshots.dealerWETHAsset = BalanceSnapshot.take(dealer, address(weth));
        assetSnapshots.userETHAsset = BalanceSnapshot.take(user, LibConstant.ETH_ADDRESS);
        assetSnapshots.userWETHAsset = BalanceSnapshot.take(user, address(weth));

        // Case 1: Tx failed due to invalid msg.value
        vm.expectRevert("SignalBuyContract: mismatch dealer token (ETH) amount");
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy{ value: 1 }(order, orderMakerSig, traderParams, crdParams);

        // Case 2: Tx succeeded
        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order)),
            order.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill)),
            DEFAULT_TRADER_PARAMS.recipient,
            ISignalBuyContract.FillReceipt(
                address(order.userToken),
                address(order.dealerToken),
                order.userTokenAmount,
                order.minDealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                0, // tokenlonFee = 0
                0 // dealerStrategyFee = 0
            )
        );
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy(order, orderMakerSig, traderParams, crdParams);

        assetSnapshots.dealerETHAsset.assertChange(0);
        assetSnapshots.dealerWETHAsset.assertChange(-int256(order.minDealerTokenAmount));
        assetSnapshots.userETHAsset.assertChange(0);
        assetSnapshots.userWETHAsset.assertChange(int256(order.minDealerTokenAmount));
    }

    function testSettlementETHToWETHWithAddedTokenlonFee() public {
        // tokenlonFeeFactor : 10%
        vm.startPrank(owner, owner);
        signalBuyContract.setFactors(1000);
        vm.warp(block.timestamp + signalBuyContract.factorActivateDelay());
        signalBuyContract.activateFactors();
        vm.stopPrank();

        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        order.dealerToken = weth;
        order.minDealerTokenAmount = 1e18;
        bytes memory orderMakerSig = _signOrder(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        // Increase dealer token amount so the dealerToken/userToken ratio is better than order's dealerToken/userToken ratio
        // to account for tokenlon fee
        fill.dealerTokenAmount = order.minDealerTokenAmount.mul(115).div(100); // 15% more

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        assetSnapshots.dealerETHAsset = BalanceSnapshot.take(dealer, LibConstant.ETH_ADDRESS);
        assetSnapshots.dealerWETHAsset = BalanceSnapshot.take(dealer, address(weth));
        assetSnapshots.userETHAsset = BalanceSnapshot.take(user, LibConstant.ETH_ADDRESS);
        assetSnapshots.userWETHAsset = BalanceSnapshot.take(user, address(weth));

        // Case 1: Tx failed due to invalid msg.value
        vm.expectRevert("SignalBuyContract: mismatch dealer token (ETH) amount");
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy{ value: 1 }(order, orderMakerSig, traderParams, crdParams);

        // Case 2: Tx succeeded
        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order)),
            order.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill)),
            DEFAULT_TRADER_PARAMS.recipient,
            ISignalBuyContract.FillReceipt(
                address(order.userToken),
                address(order.dealerToken),
                order.userTokenAmount,
                fill.dealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                fill.dealerTokenAmount.div(10), // tokenlonFee = 10% dealerTokenAmount
                0 // dealerStrategyFee = 0
            )
        );
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy{ value: fill.dealerTokenAmount }(order, orderMakerSig, traderParams, crdParams);

        assetSnapshots.dealerETHAsset.assertChange(-int256(fill.dealerTokenAmount));
        assetSnapshots.dealerWETHAsset.assertChange(0);
        assetSnapshots.userETHAsset.assertChange(0);
        assetSnapshots.userWETHAsset.assertChange(int256(fill.dealerTokenAmount.mul(9).div(10))); // 10% fee for Tokenlon
    }

    function testSettlementWETHToETHWithAddedGasFeeAndStrategyFee() public {
        SignalBuyContractLibEIP712.Order memory order = DEFAULT_ORDER;
        order.dealerToken = IERC20(LibConstant.ETH_ADDRESS);
        order.minDealerTokenAmount = 1e18;
        bytes memory orderMakerSig = _signOrder(userPrivateKey, order, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.Fill memory fill = DEFAULT_FILL;
        fill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        // Increase dealer token amount so the dealerToken/userToken ratio is better than order's dealerToken/userToken ratio
        // to account for gas fee and dealer strategy fee
        fill.dealerTokenAmount = order.minDealerTokenAmount.mul(11).div(10); // 10% more

        ISignalBuyContract.TraderParams memory traderParams = DEFAULT_TRADER_PARAMS;
        traderParams.gasFeeFactor = 50; // gasFeeFactor: 0.5%
        traderParams.dealerStrategyFeeFactor = 250; // dealerStrategyFeeFactor: 2.5%
        traderParams.dealerTokenAmount = fill.dealerTokenAmount;
        traderParams.dealerSig = _signFill(dealerPrivateKey, fill, SignatureValidator.SignatureType.EIP712);

        SignalBuyContractLibEIP712.AllowFill memory allowFill = DEFAULT_ALLOW_FILL;
        allowFill.orderHash = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order));
        allowFill.fillAmount = traderParams.dealerTokenAmount;

        ISignalBuyContract.CoordinatorParams memory crdParams = DEFAULT_CRD_PARAMS;
        crdParams.sig = _signAllowFill(coordinatorPrivateKey, allowFill, SignatureValidator.SignatureType.EIP712);

        assetSnapshots.dealerETHAsset = BalanceSnapshot.take(dealer, LibConstant.ETH_ADDRESS);
        assetSnapshots.dealerWETHAsset = BalanceSnapshot.take(dealer, address(weth));
        assetSnapshots.userETHAsset = BalanceSnapshot.take(user, LibConstant.ETH_ADDRESS);
        assetSnapshots.userWETHAsset = BalanceSnapshot.take(user, address(weth));

        // Case 1: Tx failed due to invalid msg.value
        vm.expectRevert("SignalBuyContract: mismatch dealer token (ETH) amount");
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy{ value: 1 }(order, orderMakerSig, traderParams, crdParams);

        // Case 2: Tx succeeded
        vm.expectEmit(true, true, true, true);
        emit SignalBuyFilledByTrader(
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getOrderStructHash(order)),
            order.user,
            dealer,
            getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill)),
            DEFAULT_TRADER_PARAMS.recipient,
            ISignalBuyContract.FillReceipt(
                address(order.userToken),
                address(order.dealerToken),
                order.userTokenAmount,
                fill.dealerTokenAmount,
                0, // remainingUserTokenAmount should be zero after order fully filled
                0, // tokenlonFee = 0
                fill.dealerTokenAmount.mul(3).div(100) // dealerStrategyFee = 0.5% + 2.5% = 3% dealerTokenAmount
            )
        );
        vm.prank(dealer, dealer);
        signalBuyContract.fillSignalBuy(order, orderMakerSig, traderParams, crdParams);

        assetSnapshots.dealerETHAsset.assertChange(0);
        assetSnapshots.dealerWETHAsset.assertChange(-int256(fill.dealerTokenAmount.mul(97).div(100))); // 3% fee for SignalBuy is deducted from dealerTokenAmount directly
        assetSnapshots.userETHAsset.assertChange(int256(fill.dealerTokenAmount.mul(97).div(100))); // 3% fee for SignalBuy
        assetSnapshots.userWETHAsset.assertChange(0);
    }

    /*********************************
     *        cancelSignalBuy       *
     *********************************/

    function testCannotFillCanceledOrder() public {
        SignalBuyContractLibEIP712.Order memory zeroOrder = DEFAULT_ORDER;
        zeroOrder.minDealerTokenAmount = 0;
        bytes memory cancelSig = _signOrder(userPrivateKey, zeroOrder, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.cancelSignalBuy(DEFAULT_ORDER, cancelSig);

        vm.expectRevert("SignalBuyContract: Order is cancelled");
        signalBuyContract.fillSignalBuy(DEFAULT_ORDER, DEFAULT_ORDER_MAKER_SIG, DEFAULT_TRADER_PARAMS, DEFAULT_CRD_PARAMS);
    }

    function testCannotCancelIfNotMaker() public {
        SignalBuyContractLibEIP712.Order memory zeroOrder = DEFAULT_ORDER;
        zeroOrder.minDealerTokenAmount = 0;
        bytes memory cancelSig = _signOrder(dealerPrivateKey, zeroOrder, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Cancel request is not signed by user");
        signalBuyContract.cancelSignalBuy(DEFAULT_ORDER, cancelSig);
    }

    function testCannotCancelExpiredOrder() public {
        SignalBuyContractLibEIP712.Order memory expiredOrder = DEFAULT_ORDER;
        expiredOrder.expiry = 0;
        bytes memory cancelSig = _signOrder(userPrivateKey, expiredOrder, SignatureValidator.SignatureType.EIP712);

        vm.expectRevert("SignalBuyContract: Order is expired");
        signalBuyContract.cancelSignalBuy(expiredOrder, cancelSig);
    }

    function testCannotCancelTwice() public {
        SignalBuyContractLibEIP712.Order memory zeroOrder = DEFAULT_ORDER;
        zeroOrder.minDealerTokenAmount = 0;
        bytes memory cancelSig = _signOrder(userPrivateKey, zeroOrder, SignatureValidator.SignatureType.EIP712);

        signalBuyContract.cancelSignalBuy(DEFAULT_ORDER, cancelSig);
        vm.expectRevert("SignalBuyContract: Order is cancelled already");
        signalBuyContract.cancelSignalBuy(DEFAULT_ORDER, cancelSig);
    }

    function _signOrderEIP712(
        address limitOrderAddr,
        uint256 privateKey,
        SignalBuyContractLibEIP712.Order memory order
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = SignalBuyContractLibEIP712._getOrderStructHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(limitOrderAddr), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _signFillEIP712(
        address limitOrderAddr,
        uint256 privateKey,
        SignalBuyContractLibEIP712.Fill memory fill
    ) internal returns (bytes memory sig) {
        bytes32 fillHash = SignalBuyContractLibEIP712._getFillStructHash(fill);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(limitOrderAddr), fillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _signAllowFillEIP712(
        address limitOrderAddr,
        uint256 privateKey,
        SignalBuyContractLibEIP712.AllowFill memory allowFill
    ) internal returns (bytes memory sig) {
        bytes32 allowFillHash = SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(limitOrderAddr), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function dealWallet(address[] memory _wallet, uint256 _amount) internal {
        // Deal 100 ETH to each account
        for (uint256 i = 0; i < _wallet.length; i++) {
            deal(_wallet[i], _amount);
        }
    }

    function setEOABalanceAndApprove(
        address eoa,
        IERC20[] memory tokens,
        uint256 amount
    ) internal {
        require(address(signalBuyContract) != address(0), "System contracts not setup yet");
        vm.startPrank(eoa);
        for (uint256 i = 0; i < tokens.length; i++) {
            setERC20Balance(address(tokens[i]), eoa, amount);
            tokens[i].safeApprove(address(signalBuyContract), type(uint256).max);
        }
        vm.stopPrank();
    }

    function _signOrder(
        uint256 privateKey,
        SignalBuyContractLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = SignalBuyContractLibEIP712._getOrderStructHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), orderHash);

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
        SignalBuyContractLibEIP712.Order memory order,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = SignalBuyContractLibEIP712._getOrderStructHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), orderHash);
        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }

    function _signFill(
        uint256 privateKey,
        SignalBuyContractLibEIP712.Fill memory fill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 fillHash = SignalBuyContractLibEIP712._getFillStructHash(fill);
        bytes32 EIP712SignDigest = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), fillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, uint8(sigType));
    }

    function _signFillWithOldEIP712Method(
        uint256 privateKey,
        SignalBuyContractLibEIP712.Fill memory fill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 fillHash = SignalBuyContractLibEIP712._getFillStructHash(fill);
        bytes32 EIP712SignDigest = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), fillHash);
        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }

    function _signAllowFill(
        uint256 privateKey,
        SignalBuyContractLibEIP712.AllowFill memory allowFill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 allowFillHash = SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, uint8(sigType));
    }

    function _signAllowFillWithOldEIP712Method(
        uint256 privateKey,
        SignalBuyContractLibEIP712.AllowFill memory allowFill,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        bytes32 allowFillHash = SignalBuyContractLibEIP712._getAllowFillStructHash(allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(signalBuyContract.EIP712_DOMAIN_SEPARATOR(), allowFillHash);
        require(sigType == SignatureValidator.SignatureType.EIP712, "Invalid signature type");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(sigType));
    }
}
