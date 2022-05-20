// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/AMMWrapperWithPath.sol";
import "contracts/AMMQuoter.sol";
import "contracts/interfaces/IPermanentStorage.sol";
import "contracts/interfaces/ISpender.sol";
import "contracts/interfaces/IBalancerV2Vault.sol";
import "contracts/utils/AMMLibEIP712.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/StrategySharedSetup.sol";
import "contracts-test/utils/UniswapV3Util.sol";

contract AMMWrapperWithPathTest is StrategySharedSetup {
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 constant BPS_MAX = 10000;
    event Swapped(AMMWrapperWithPath.TxMetaData, AMMLibEIP712.Order order);

    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address relayer = address(0x133702);
    address[] wallet = [user, relayer];

    AMMWrapperWithPath ammWrapperWithPath;
    AMMQuoter ammQuoter;
    IERC20 weth = IERC20(Addresses.WETH_ADDRESS);
    IERC20 usdt = IERC20(Addresses.USDT_ADDRESS);
    IERC20 usdc = IERC20(Addresses.USDC_ADDRESS);
    IERC20 dai = IERC20(Addresses.DAI_ADDRESS);
    IERC20 wbtc = IERC20(Addresses.WBTC_ADDRESS);
    IERC20[] tokens = [weth, usdt, usdc, dai, wbtc];

    uint256 SUBSIDY_FACTOR = 3;
    uint256 DEADLINE = block.timestamp + 1;
    AMMLibEIP712.Order DEFAULT_ORDER;
    // UniswapV3
    uint256 SINGLE_POOL_SWAP_TYPE = 1;
    uint256 MULTI_POOL_SWAP_TYPE = 2;
    address[] DEFAULT_MULTI_HOP_PATH;
    uint24[] DEFAULT_MULTI_HOP_POOL_FEES;
    // BalancerV2
    bytes32 constant BALANCER_DAI_USDT_USDC_POOL = 0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063;
    bytes32 constant BALANCER_WETH_DAI_POOL = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
    bytes32 constant BALANCER_WETH_USDC_POOL = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        setUpSystemContracts();
        ammQuoter = new AMMQuoter(IPermanentStorage(permanentStorage), address(weth));
        address[] memory relayerListAddress = new address[](1);
        relayerListAddress[0] = relayer;
        bool[] memory relayerListBool = new bool[](1);
        relayerListBool[0] = true;
        permanentStorage.setRelayersValid(relayerListAddress, relayerListBool);

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        setEOABalanceAndApprove(user, tokens, 100);

        // Default order
        DEFAULT_ORDER = AMMLibEIP712.Order(
            Addresses.UNISWAP_V3_ADDRESS, // makerAddr
            address(usdc), // takerAssetAddr
            address(dai), // makerAssetAddr
            100 * 1e6, // takerAssetAmount
            90 * 1e18, // makerAssetAmount
            user, // userAddr
            payable(user), // receiverAddr
            uint256(1234), // salt
            DEADLINE // deadline
        );
        DEFAULT_MULTI_HOP_PATH = new address[](3);
        DEFAULT_MULTI_HOP_PATH[0] = DEFAULT_ORDER.takerAssetAddr;
        DEFAULT_MULTI_HOP_PATH[1] = address(weth);
        DEFAULT_MULTI_HOP_PATH[2] = DEFAULT_ORDER.makerAssetAddr;
        DEFAULT_MULTI_HOP_POOL_FEES = new uint24[](2);
        DEFAULT_MULTI_HOP_POOL_FEES[0] = FEE_MEDIUM;
        DEFAULT_MULTI_HOP_POOL_FEES[1] = FEE_MEDIUM;

        // Label addresses for easier debugging
        vm.label(user, "User");
        vm.label(relayer, "Relayer");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammWrapperWithPath), "AMMWrapperWithPathContract");
        vm.label(address(weth), "WETH");
        vm.label(address(usdt), "USDT");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(address(wbtc), "WBTC");
        vm.label(Addresses.UNISWAP_V2_ADDRESS, "UniswapV2");
        vm.label(Addresses.SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(Addresses.UNISWAP_V3_ADDRESS, "UniswapV3");
        vm.label(Addresses.CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
        vm.label(Addresses.CURVE_TRICRYPTO2_POOL_ADDRESS, "CurveTriCryptoPool");
    }

    function _deployStrategyAndUpgrade() internal override returns (address) {
        ammWrapperWithPath = new AMMWrapperWithPath(
            address(this), // This contract would be the operator
            SUBSIDY_FACTOR,
            address(userProxy),
            ISpender(address(spender)),
            permanentStorage,
            IWETH(address(weth))
        );
        // Setup
        userProxy.upgradeAMMWrapper(address(ammWrapperWithPath), true);
        permanentStorage.upgradeAMMWrapper(address(ammWrapperWithPath));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(ammWrapperWithPath), true);
        return address(ammWrapperWithPath);
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupAllowance() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].allowance(user, address(allowanceTarget)), type(uint256).max);
        }
    }

    function testSetupAMMWrapperWithPath() public {
        assertEq(ammWrapperWithPath.operator(), address(this));
        assertEq(ammWrapperWithPath.subsidyFactor(), SUBSIDY_FACTOR);
        assertEq(ammWrapperWithPath.userProxy(), address(userProxy));
        assertEq(address(ammWrapperWithPath.spender()), address(spender));
        assertEq(userProxy.ammWrapperAddr(), address(ammWrapperWithPath));
        assertEq(permanentStorage.ammWrapperAddr(), address(ammWrapperWithPath));
        assertTrue(spender.isAuthorized(address(ammWrapperWithPath)));
        assertTrue(permanentStorage.isRelayerValid(relayer));
    }

    /*********************************
     *          Test: trade          *
     *********************************/

    function testCannotTradeWithInvalidSig() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(otherPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, bytes(""), new address[](0));

        vm.expectRevert("AMMWrapper: invalid user signature");
        userProxy.toAMM(payload);
    }

    function testTradeSushiswap_SingleHop() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.SUSHISWAP_ADDRESS;
        order.makerAssetAddr = Addresses.ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, bytes(""), new address[](0));

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testTradeSushiswap_MultiHop() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.SUSHISWAP_ADDRESS;
        order.makerAssetAddr = Addresses.ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        path[1] = address(dai);
        path[2] = address(weth);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, bytes(""), path);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testTradeCurveVersion1() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.CURVE_USDT_POOL_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(1), new address[](0));

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testTradeCurveVersion2() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.CURVE_TRICRYPTO2_POOL_ADDRESS;
        order.takerAssetAddr = address(usdt);
        order.takerAssetAmount = 100 * 1e6;
        order.makerAssetAddr = address(wbtc);
        order.makerAssetAmount = 0.001 * 1e8;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testCannotTradeCurveWithMismatchVersion_Version1PoolAndSpecifyVersion2() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.CURVE_USDT_POOL_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        // Curve USDT pool is version 1 but we input version 2
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(2), new address[](0));

        vm.expectRevert("AMMWrapper: Curve v2 no underlying");
        userProxy.toAMM(payload);
    }

    function testCannotTradeCurveWithMismatchVersion_Version2PoolAndSpecifyVersion1() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.CURVE_TRICRYPTO2_POOL_ADDRESS;
        order.takerAssetAddr = address(usdt);
        order.takerAssetAmount = 100 * 1e6;
        order.makerAssetAddr = address(wbtc);
        order.makerAssetAmount = 0.001 * 1e8;
        bytes memory sig = _signTrade(userPrivateKey, order);
        // Curve Tricrypto2 pool is version 1 but we input version 1
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeCurveData(1), new address[](0));

        vm.expectRevert("AMMWrapper: No output from curve");
        userProxy.toAMM(payload);
    }

    function testCannotTradeUniswapV3_SinglePool_InvalidSwapType() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapSinglePoolData(0, FEE_MEDIUM), new address[](0));

        vm.expectRevert("AMMWrapper: unsupported UniswapV3 swap type");
        userProxy.toAMM(payload);

        payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapSinglePoolData(3, FEE_MEDIUM), new address[](0));

        // No revert string as it violates SwapType enum's sanity check
        vm.expectRevert();
        userProxy.toAMM(payload);
    }

    function testCannotTradeUniswapV3_SinglePool_InvalidPoolFee() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, 0), new address[](0));

        // No revert string for invalid pool fee
        vm.expectRevert();
        userProxy.toAMM(payload);

        payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapSinglePoolData(3, type(uint24).max), new address[](0));

        // No revert string for invalid pool fee
        vm.expectRevert();
        userProxy.toAMM(payload);
    }

    function testTradeUniswapV3_ExactInputSingle() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAssetAddr = Addresses.ETH_ADDRESS;
        order.makerAssetAmount = 0.001 ether;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, FEE_MEDIUM), new address[](0));

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testCannotTradeUniswapV3_MultiPool_InvalidPath_InvalidPathFormat() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        bytes memory garbageData = new bytes(0);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, abi.encode(MULTI_POOL_SWAP_TYPE, garbageData), path);

        vm.expectRevert("toAddress_outOfBounds");
        userProxy.toAMM(payload);

        garbageData = new bytes(2);
        garbageData[0] = "5";
        garbageData[1] = "5";
        payload = _genTradePayload(order, feeFactor, sig, abi.encode(MULTI_POOL_SWAP_TYPE, garbageData), path);

        vm.expectRevert("toAddress_outOfBounds");
        userProxy.toAMM(payload);
    }

    function testCannotTradeUniswapV3_MultiPool_InvalidPath_InvalidFeeFormat() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](1);
        path[0] = order.takerAssetAddr;
        uint24[] memory fees = new uint24[](0); // No fees specified
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees), path);

        vm.expectRevert("toUint24_outOfBounds");
        userProxy.toAMM(payload);
    }

    function testCannotTradeUniswapV3_MultiPool_InvalidPath_MismatchAsset() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        path[0] = user;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees), path);

        vm.expectRevert("UniswapV3: first element of path must match token in");
        userProxy.toAMM(payload);

        path = DEFAULT_MULTI_HOP_PATH;
        path[2] = user;
        payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees), path);
        vm.expectRevert("UniswapV3: last element of path must match token out");
        userProxy.toAMM(payload);
    }

    function testTradeUniswapV3_ExactInput_SingleHop() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees), path);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testTradeUniswapV3_ExactInput_MultiHop() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees), path);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testCannotTradeBalancerV2_NoSwapSteps() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](2);
        path[0] = order.takerAssetAddr;
        path[1] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](0); // Empty SwapSteps
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 requires at least one swap step");
        userProxy.toAMM(payload);
    }

    function testCannotTradeBalancerV2_NoPath() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](0); // Empty path
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: path length must be at least two");
        userProxy.toAMM(payload);
    }

    function testCannotTradeBalancerV2_MismatchAsset() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](3);
        path[0] = order.takerAssetAddr;
        path[1] = address(weth);
        path[2] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        // AssetIn in first SwapStep (weth) is not taker asset
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 first step asset in should match taker asset");
        userProxy.toAMM(payload);

        // AssetOut in first SwapStep (weth) is not maker asset
        swapSteps[0].poolId = BALANCER_WETH_DAI_POOL;
        swapSteps[0].assetInIndex = 0;
        swapSteps[0].assetOutIndex = 1;
        payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 last step asset out should match maker asset");
        userProxy.toAMM(payload);
    }

    function testTradeBalancerV2_SingleHop() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = new address[](2);
        path[0] = order.takerAssetAddr;
        path[1] = order.makerAssetAddr;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testCannotTradeBalancerV2_InvalidAmountInSwapSteps() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](2);
        uint256 invalidFirstSwapStepAssetInAmount = order.takerAssetAmount + 1;
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            invalidFirstSwapStepAssetInAmount, // amount
            new bytes(0) // userData
        );
        swapSteps[1] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_DAI_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            0, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 cannot swap more than taker asset amount");
        userProxy.toAMM(payload);

        uint256 invalidOtherSwapStepAssetInAmount = 999; // Amount of other SwapSteps must be zero
        swapSteps[0].amount = order.takerAssetAmount; // Restore amount of first SwapStep
        swapSteps[1].amount = invalidOtherSwapStepAssetInAmount;
        payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        vm.expectRevert("AMMWrapper: BalancerV2 can only specify amount at first step");
        userProxy.toAMM(payload);
    }

    function testTradeBalancerV2_MultiHop() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        order.makerAddr = Addresses.BALANCER_V2_ADDRESS;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](2);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            order.takerAssetAmount, // amount
            new bytes(0) // userData
        );
        swapSteps[1] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_WETH_DAI_POOL, // poolId
            1, // assetInIndex
            2, // assetOutIndex
            0, // amount
            new bytes(0) // userData
        );
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeBalancerData(swapSteps), path);

        BalanceSnapshot.Snapshot memory userTakerAsset = BalanceSnapshot.take(user, order.takerAssetAddr);
        BalanceSnapshot.Snapshot memory userMakerAsset = BalanceSnapshot.take(user, order.makerAssetAddr);

        userProxy.toAMM(payload);

        userTakerAsset.assertChange(-int256(order.takerAssetAmount));
        userMakerAsset.assertChangeGt(int256(order.makerAssetAmount));
    }

    function testCannotTradeWithSamePayloadAgain() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, _encodeUniswapSinglePoolData(SINGLE_POOL_SWAP_TYPE, FEE_MEDIUM), new address[](0));

        userProxy.toAMM(payload);

        vm.expectRevert("PermanentStorage: transaction seen before");
        userProxy.toAMM(payload);
    }

    /*********************************
     *       Test: emit event        *
     *********************************/

    function testEmitSwappedEvent() public {
        uint256 feeFactor = 0;
        AMMLibEIP712.Order memory order = DEFAULT_ORDER;
        bytes memory sig = _signTrade(userPrivateKey, order);
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        bytes memory makerSpecificData = _encodeUniswapMultiPoolData(MULTI_POOL_SWAP_TYPE, path, fees);
        bytes memory payload = _genTradePayload(order, feeFactor, sig, makerSpecificData, path);
        // Set subsidy factor to 0
        ammWrapperWithPath.setSubsidyFactor(0);

        uint256 expectedOutAmount = ammQuoter.getMakerOutAmountWithPath(
            order.makerAddr,
            order.takerAssetAddr,
            order.makerAssetAddr,
            order.takerAssetAmount,
            path,
            makerSpecificData
        );
        vm.expectEmit(false, false, false, true);
        AMMWrapperWithPath.TxMetaData memory txMetaData = AMMWrapper.TxMetaData(
            "Uniswap V3", // source
            AMMLibEIP712._getOrderHash(order), // transactionHash
            expectedOutAmount, // settleAmount: no fee so settled amount is the same as received amount
            expectedOutAmount, // receivedAmount
            uint16(feeFactor), // Fee factor: 0
            uint16(0) // Subsidy factor: 0
        );
        emit Swapped(txMetaData, order);
        userProxy.toAMM(payload);
    }

    /*********************************
     *             Helpers           *
     *********************************/

    function _encodeCurveData(uint256 version) internal returns (bytes memory) {
        return abi.encode(version);
    }

    function _encodeUniswapSinglePoolData(uint256 swapType, uint24 poolFee) internal returns (bytes memory) {
        return abi.encode(swapType, poolFee);
    }

    function _encodeUniswapMultiPoolData(
        uint256 swapType,
        address[] memory path,
        uint24[] memory poolFees
    ) internal returns (bytes memory) {
        return abi.encode(swapType, encodePath(path, poolFees));
    }

    function _encodeBalancerData(IBalancerV2Vault.BatchSwapStep[] memory swapSteps) internal returns (bytes memory) {
        return abi.encode(swapSteps);
    }

    function _getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        bytes32 EIP712_DOMAIN_SEPARATOR = ammWrapperWithPath.EIP712_DOMAIN_SEPARATOR();
        return keccak256(abi.encodePacked(EIP191_HEADER, EIP712_DOMAIN_SEPARATOR, structHash));
    }

    function _signTrade(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = _getEIP712Hash(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _genTradePayload(
        AMMLibEIP712.Order memory order,
        uint256 feeFactor,
        bytes memory sig,
        bytes memory makerSpecificData,
        address[] memory path
    ) internal view returns (bytes memory payload) {
        return
            abi.encodeWithSignature(
                "trade((address,address,address,uint256,uint256,address,address,uint256,uint256),uint256,bytes,bytes,address[])",
                order,
                feeFactor,
                sig,
                makerSpecificData,
                path
            );
    }
}
