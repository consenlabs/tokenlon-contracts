// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts/AMMQuoter.sol";
import "contracts/interfaces/IBalancerV2Vault.sol";
import "contracts/interfaces/IPermanentStorage.sol";
import "contracts-test/utils/AMMUtil.sol";
import "contracts-test/utils/StrategySharedSetup.sol";

contract AMMQuoterTest is StrategySharedSetup {
    uint256 constant BPS_MAX = 10000;

    AMMQuoter ammQuoter;

    address DEFAULT_MAKER_ADDR = UNISWAP_V2_ADDRESS;
    address DEFAULT_TAKER_ASSET_ADDR = DAI_ADDRESS;
    address DEFAULT_MAKER_ASSET_ADDR = USDT_ADDRESS;
    uint256 DEFAULT_TAKER_ASSET_AMOUNT = 100 * 1e18;
    uint256 DEFAULT_MAKER_ASSET_AMOUNT = 100 * 1e6;
    address[] EMPTY_PATH = new address[](0);
    address[] DEFAULT_SINGLE_HOP_PATH = [DEFAULT_TAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_ADDR];
    address[] DEFAULT_MULTI_HOP_PATH = [DEFAULT_TAKER_ASSET_ADDR, WETH_ADDRESS, DEFAULT_MAKER_ASSET_ADDR];
    uint24[] DEFAULT_MULTI_HOP_POOL_FEES = [FEE_MEDIUM, FEE_MEDIUM];

    // BalancerV2
    bytes32 constant BALANCER_DAI_USDT_USDC_POOL = 0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063;
    bytes32 constant BALANCER_WETH_DAI_POOL = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
    bytes32 constant BALANCER_WETH_USDC_POOL = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;

    // effectively a "beforeEach" block
    function setUp() public {
        // Setup
        _deployPermanentStorageAndProxy();
        ammQuoter = new AMMQuoter(IPermanentStorage(permanentStorage), WETH_ADDRESS);

        // Label addresses for easier debugging
        vm.label(address(this), "TestingContract");
        vm.label(address(ammQuoter), "AMMQuoterContract");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(UNISWAP_V3_ADDRESS, "UniswapV3");
        vm.label(UNISWAP_V3_QUOTER_ADDRESS, "UniswapV3Quoter");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetupAMMQuoter() public {
        assertEq(address(ammQuoter.permStorage()), address(permanentStorage));
        assertEq(ammQuoter.weth(), WETH_ADDRESS);
    }

    /*************************************
     *      Test: getMakerOutAmount      *
     *************************************/

    function testCannotGetMakerOutAmount_InvalidMaker() public {
        vm.expectRevert("PermanentStorage: invalid pair");
        ammQuoter.getMakerOutAmount(address(0xdead), DEFAULT_TAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_ADDR, DEFAULT_TAKER_ASSET_AMOUNT);
    }

    function testGetMakerOutAmount_UniswapV2() public {
        uint256 amountOut = ammQuoter.getMakerOutAmount(DEFAULT_MAKER_ADDR, DEFAULT_TAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_ADDR, DEFAULT_TAKER_ASSET_AMOUNT);
        assertGt(amountOut, 0);
    }

    function testCannotGetMakerOutAmount_Curve_InvalidSwapMethod() public {
        vm.expectRevert("PermanentStorage: invalid pair");
        ammQuoter.getMakerOutAmount(CURVE_USDT_POOL_ADDRESS, address(0xdead), DEFAULT_MAKER_ASSET_ADDR, DEFAULT_TAKER_ASSET_AMOUNT);
    }

    function testGetMakerOutAmount_Curve() public {
        uint256 amountOut = ammQuoter.getMakerOutAmount(
            CURVE_USDT_POOL_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT
        );
        assertGt(amountOut, 0);
    }

    /*********************************************
     *      Test: getMakerOutAmountWithPath      *
     *********************************************/

    function testCannotGetMakerOutAmountWithPath_InvalidMaker() public {
        vm.expectRevert("PermanentStorage: invalid pair");
        ammQuoter.getMakerOutAmountWithPath(
            address(0xdead),
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            bytes("")
        );
    }

    function testGetMakerOutAmountWithPath_UniswapV2() public {
        uint256 amountOut = ammQuoter.getMakerOutAmountWithPath(
            DEFAULT_MAKER_ADDR,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            bytes("")
        );
        assertGt(amountOut, 0);
    }

    function testCannotGetMakerOutAmountWithPath_UniswapV3_SingleHop_InvalidSwapType() public {
        uint256 swapType = 3;
        vm.expectRevert("AMMQuoter: Invalid UniswapV3 swap type");
        ammQuoter.getMakerOutAmountWithPath(
            UNISWAP_V3_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            EMPTY_PATH,
            _encodeUniswapSinglePoolData(swapType, FEE_LOW)
        );
    }

    function testGetMakerOutAmountWithPath_UniswapV3_SingleHop() public {
        uint256 swapType = 1;
        uint256 amountOut = ammQuoter.getMakerOutAmountWithPath(
            UNISWAP_V3_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            EMPTY_PATH,
            _encodeUniswapSinglePoolData(swapType, FEE_LOW)
        );
        assertGt(amountOut, 0);
    }

    function testGetMakerOutAmountWithPath_UniswapV3_MultiHop() public {
        uint256 swapType = 2;
        address[] memory path = DEFAULT_MULTI_HOP_PATH;
        uint24[] memory fees = DEFAULT_MULTI_HOP_POOL_FEES;
        uint256 amountOut = ammQuoter.getMakerOutAmountWithPath(
            UNISWAP_V3_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            EMPTY_PATH,
            _encodeUniswapMultiPoolData(swapType, path, fees)
        );
        assertGt(amountOut, 0);
    }

    function testCannotGetMakerOutAmountWithPath_Balancer_SingleHop_InvalidAssetOrder() public {
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        // Reverse index of assetIn and assetOut
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            1, // assetInIndex
            0, // assetOutIndex
            DEFAULT_TAKER_ASSET_AMOUNT, // amount
            new bytes(0) // userData
        );
        vm.expectRevert("AMMQuoter: wrong amount from balancer pool");
        ammQuoter.getMakerOutAmountWithPath(
            BALANCER_V2_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            _encodeBalancerData(swapSteps)
        );
    }

    function testGetMakerOutAmountWithPath_Balancer_SingleHop() public {
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            DEFAULT_TAKER_ASSET_AMOUNT, // amount
            new bytes(0) // userData
        );
        uint256 amountOut = ammQuoter.getMakerOutAmountWithPath(
            BALANCER_V2_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            // path,
            DEFAULT_SINGLE_HOP_PATH,
            _encodeBalancerData(swapSteps)
        );
        assertGt(amountOut, 0);
    }

    function testGetMakerOutAmountWithPath_Balancer_MultiHop() public {
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            DEFAULT_TAKER_ASSET_AMOUNT, // amount
            new bytes(0) // userData
        );
        uint256 amountOut = ammQuoter.getMakerOutAmountWithPath(
            BALANCER_V2_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            _encodeBalancerData(swapSteps)
        );
        assertGt(amountOut, 0);
    }

    function testCannotGetMakerOutAmountWithPath_Curve_MismatchVersion() public {
        uint256 curveVersion = 3;
        vm.expectRevert("AMMQuoter: Invalid Curve version");
        ammQuoter.getMakerOutAmountWithPath(
            CURVE_USDT_POOL_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            EMPTY_PATH,
            _encodeCurveData(curveVersion)
        );
    }

    function testGetMakerOutAmountWithPath_Curve_Version1() public {
        uint256 curveVersion = 1;
        uint256 amountOut = ammQuoter.getMakerOutAmountWithPath(
            CURVE_USDT_POOL_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            EMPTY_PATH,
            _encodeCurveData(curveVersion)
        );
        assertGt(amountOut, 0);
    }

    /************************************
     *      Test: getBestOutAmount      *
     ************************************/

    function testGetBestOutAmount() public {
        address[] memory makers = new address[](3);
        makers[0] = UNISWAP_V2_ADDRESS;
        makers[1] = SUSHISWAP_ADDRESS;
        makers[2] = CURVE_USDT_POOL_ADDRESS;
        (address bestMaker, uint256 bestAmount) = ammQuoter.getBestOutAmount(
            makers,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT
        );
        assertFalse(bestMaker == address(0));
        assertGt(bestAmount, 0);
    }

    /*************************************
     *      Test: getTakerInAmount      *
     *************************************/

    function testCannotGetTakerInAmount_InvalidMaker() public {
        vm.expectRevert("PermanentStorage: invalid pair");
        ammQuoter.getTakerInAmount(address(0xdead), DEFAULT_TAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_ADDR, DEFAULT_TAKER_ASSET_AMOUNT);
    }

    function testGetTakerInAmount_UniswapV2() public {
        uint256 amountOut = ammQuoter.getTakerInAmount(DEFAULT_MAKER_ADDR, DEFAULT_TAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_AMOUNT);
        assertGt(amountOut, 0);
    }

    function testCannotGetTakerInAmount_Curve_InvalidSwapMethod() public {
        vm.expectRevert("PermanentStorage: invalid pair");
        ammQuoter.getTakerInAmount(CURVE_USDT_POOL_ADDRESS, address(0xdead), DEFAULT_MAKER_ASSET_ADDR, DEFAULT_TAKER_ASSET_AMOUNT);
    }

    function testGetTakerInAmount_Curve() public {
        uint256 amountOut = ammQuoter.getTakerInAmount(CURVE_USDT_POOL_ADDRESS, DEFAULT_TAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_ADDR, DEFAULT_MAKER_ASSET_AMOUNT);
        assertGt(amountOut, 0);
    }

    /*********************************************
     *      Test: getTakerInAmountWithPath      *
     *********************************************/

    function testCannotGetTakerInAmountWithPath_InvalidMaker() public {
        vm.expectRevert("PermanentStorage: invalid pair");
        ammQuoter.getTakerInAmountWithPath(
            address(0xdead),
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_TAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            bytes("")
        );
    }

    function testGetTakerInAmountWithPath_UniswapV2() public {
        uint256 amountOut = ammQuoter.getTakerInAmountWithPath(
            DEFAULT_MAKER_ADDR,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            bytes("")
        );
        assertGt(amountOut, 0);
    }

    function testCannotGetTakerInAmountWithPath_Balancer_SingleHop_InvalidAssetOrder() public {
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        // Reverse index of assetIn and assetOut
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            1, // assetInIndex
            0, // assetOutIndex
            DEFAULT_MAKER_ASSET_AMOUNT, // amount
            new bytes(0) // userData
        );
        vm.expectRevert("AMMQuoter: wrong amount from balancer pool");
        ammQuoter.getTakerInAmountWithPath(
            BALANCER_V2_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            _encodeBalancerData(swapSteps)
        );
    }

    function testGetTakerInAmountWithPath_Balancer_SingleHop() public {
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            DEFAULT_MAKER_ASSET_AMOUNT, // amount
            new bytes(0) // userData
        );
        uint256 amountOut = ammQuoter.getTakerInAmountWithPath(
            BALANCER_V2_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_AMOUNT,
            // path,
            DEFAULT_SINGLE_HOP_PATH,
            _encodeBalancerData(swapSteps)
        );
        assertGt(amountOut, 0);
    }

    function testGetTakerInAmountWithPath_Balancer_MultiHop() public {
        IBalancerV2Vault.BatchSwapStep[] memory swapSteps = new IBalancerV2Vault.BatchSwapStep[](1);
        swapSteps[0] = IBalancerV2Vault.BatchSwapStep(
            BALANCER_DAI_USDT_USDC_POOL, // poolId
            0, // assetInIndex
            1, // assetOutIndex
            DEFAULT_MAKER_ASSET_AMOUNT, // amount
            new bytes(0) // userData
        );
        uint256 amountOut = ammQuoter.getTakerInAmountWithPath(
            BALANCER_V2_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_AMOUNT,
            DEFAULT_SINGLE_HOP_PATH,
            _encodeBalancerData(swapSteps)
        );
        assertGt(amountOut, 0);
    }

    function testCannotGetTakerInAmountWithPath_Curve_MismatchVersion() public {
        uint256 curveVersion = 3;
        vm.expectRevert("AMMQuoter: Invalid Curve version");
        ammQuoter.getTakerInAmountWithPath(
            CURVE_USDT_POOL_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_AMOUNT,
            EMPTY_PATH,
            _encodeCurveData(curveVersion)
        );
    }

    function testGetTakerInAmountWithPath_Curve_Version1() public {
        uint256 curveVersion = 1;
        uint256 amountOut = ammQuoter.getTakerInAmountWithPath(
            CURVE_USDT_POOL_ADDRESS,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_AMOUNT,
            EMPTY_PATH,
            _encodeCurveData(curveVersion)
        );
        assertGt(amountOut, 0);
    }

    /************************************
     *      Test: getBestInAmount      *
     ************************************/

    function testGetBestInAmount() public {
        address[] memory makers = new address[](3);
        makers[0] = UNISWAP_V2_ADDRESS;
        makers[1] = SUSHISWAP_ADDRESS;
        makers[2] = CURVE_USDT_POOL_ADDRESS;
        (address bestMaker, uint256 bestAmount) = ammQuoter.getBestInAmount(
            makers,
            DEFAULT_TAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_ADDR,
            DEFAULT_MAKER_ASSET_AMOUNT
        );
        assertFalse(bestMaker == address(0));
        assertGt(bestAmount, 0);
    }
}
