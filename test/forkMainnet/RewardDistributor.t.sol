// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "contracts/interfaces/IUniswapRouterV2.sol";
import "contracts/interfaces/IUniswapV3Quoter.sol";
import { ISwapRouter as IUniswapRouterV3 } from "contracts/interfaces/IUniswapV3SwapRouter.sol";
import "contracts/Lon.sol";
import "contracts/LONStaking.sol";
import "contracts/RewardDistributor.sol";
import "contracts/xLON.sol";

import "contracts-test/mocks/MockContract.sol";
import "contracts-test/mocks/MockStrategy.sol";
import "contracts-test/utils/Addresses.sol";
import "contracts-test/utils/BalanceSnapshot.sol";
import "contracts-test/utils/UniswapV3Util.sol";

contract RewardDistributorTest is Test {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    uint256 constant COOLDOWN_IN_DAYS = 7;
    uint256 constant BPS_RAGE_EXIT_PENALTY = 500;

    uint32 constant MIN_BUYBACK_INTERVAL = 3600;
    uint32 constant BUYBACK_INTERVAL = 86400;
    uint8 constant MINING_FACTOR = 100;

    address user = address(0x133700);
    address treasury = address(0x133701);
    address miningTreasury = address(0x133702);
    address feeTokenRecipient = address(0x133703);

    IUniswapRouterV2 uniswapV2 = IUniswapRouterV2(UNISWAP_V2_ADDRESS);
    IUniswapRouterV2 sushiswap = IUniswapRouterV2(SUSHISWAP_ADDRESS);
    IUniswapRouterV3 uniswapV3 = IUniswapRouterV3(UNISWAP_V3_ADDRESS);
    IUniswapV3Quoter uniswapV3Quoter = IUniswapV3Quoter(UNISWAP_V3_QUOTER_ADDRESS);

    Lon lon = Lon(LON_ADDRESS);
    IERC20 usdt = IERC20(USDT_ADDRESS);
    IERC20 crv = IERC20(CRV_ADDRESS);

    MockStrategy[] strategies = [new MockStrategy(), new MockStrategy()];
    MockContract lonStaking = new MockContract();
    RewardDistributor rewardDistributor;

    struct SetFeeTokenParams {
        address feeTokenAddr;
        uint8 exchangeIndex;
        address[] path;
        uint8 LFactor;
        uint8 RFactor;
        bool enable;
        uint256 minBuy;
        uint256 maxBuy;
    }

    uint8 constant SUSHISWAP_EXCHANGE_INDEX = 0;
    uint8 constant UNISWAPV2_EXCHANGE_INDEX = 1;
    uint256[] EXCHANGE_INDEXES = [uint256(SUSHISWAP_EXCHANGE_INDEX), uint256(UNISWAPV2_EXCHANGE_INDEX)];
    address[] EXCHANGE_ADDRESSES = [SUSHISWAP_ADDRESS, UNISWAP_V2_ADDRESS];

    address[] LON_FEE_TOKEN_PATH = [address(lon), address(lon)];
    SetFeeTokenParams LON_FEE_TOKEN =
        SetFeeTokenParams({
            feeTokenAddr: address(lon),
            exchangeIndex: UNISWAPV2_EXCHANGE_INDEX,
            path: LON_FEE_TOKEN_PATH,
            LFactor: 0,
            RFactor: 40,
            enable: true,
            minBuy: 10,
            maxBuy: 100
        });

    address[] USDT_FEE_TOKEN_PATH = [address(usdt), WETH_ADDRESS, address(lon)];
    SetFeeTokenParams USDT_FEE_TOKEN =
        SetFeeTokenParams({
            feeTokenAddr: address(usdt),
            exchangeIndex: UNISWAPV2_EXCHANGE_INDEX,
            path: USDT_FEE_TOKEN_PATH,
            LFactor: 20,
            RFactor: 40,
            enable: true,
            minBuy: 10,
            maxBuy: 100 * 1e6
        });

    address[] CRV_FEE_TOKEN_PATH = [address(crv), WETH_ADDRESS, address(lon)];
    SetFeeTokenParams CRV_FEE_TOKEN =
        SetFeeTokenParams({
            feeTokenAddr: address(crv),
            exchangeIndex: SUSHISWAP_EXCHANGE_INDEX,
            path: CRV_FEE_TOKEN_PATH,
            LFactor: 20,
            RFactor: 40,
            enable: true,
            minBuy: 10,
            maxBuy: 10 * 1e18
        });

    function setUp() public {
        rewardDistributor = new RewardDistributor(
            address(lon),
            // Use this testing contract as owner and operator
            address(this), // owner
            address(this), // operator
            BUYBACK_INTERVAL,
            MINING_FACTOR,
            treasury,
            address(lonStaking),
            miningTreasury,
            feeTokenRecipient
        );
        // Set exchanges
        rewardDistributor.setExchangeAddrs(EXCHANGE_INDEXES, EXCHANGE_ADDRESSES);
        address[] memory strategyAddrs = new address[](strategies.length);
        // Balance of strategies will sum up to max buy of fee tokens
        for (uint256 i = 0; i < strategies.length; i++) {
            MockStrategy strategy = strategies[i];
            strategyAddrs[i] = address(strategy);
            vm.startPrank(address(strategy));
            // LON
            deal(address(lon), address(strategy), LON_FEE_TOKEN.maxBuy / strategies.length, true);
            IERC20(lon).safeApprove(address(rewardDistributor), type(uint256).max);
            // USDT
            deal(address(usdt), address(strategy), USDT_FEE_TOKEN.maxBuy / strategies.length, true);
            usdt.safeApprove(address(rewardDistributor), type(uint256).max);
            // CRV
            deal(address(crv), address(strategy), CRV_FEE_TOKEN.maxBuy / strategies.length, true);
            crv.safeApprove(address(rewardDistributor), type(uint256).max);
            vm.stopPrank();
        }
        _setStrategyAddrs(strategyAddrs);

        vm.prank(lon.owner());
        lon.setMinter(address(rewardDistributor));

        // Deal 100 ETH to user
        deal(user, 100 ether);

        vm.label(user, "User");
        vm.label(treasury, "Treasury");
        vm.label(miningTreasury, "MiningTreasury");
        vm.label(feeTokenRecipient, "FeeTokenRecipient");
        vm.label(address(this), "TestingContract");
        vm.label(address(uniswapV2), "UniswapV2");
        vm.label(address(sushiswap), "Sushiswap");
        vm.label(address(uniswapV3), "UniswapV3");
        vm.label(address(uniswapV3Quoter), "UniswapV3Quoter");
        vm.label(address(usdt), "USDT");
        vm.label(address(lon), "LON");
        vm.label(address(lonStaking), "LONStaking");
        vm.label(address(rewardDistributor), "RewardDistributor");
    }

    /*********************************
     *          Test: setup          *
     *********************************/

    function testSetup() public {
        address minter = lon.minter();
        assertEq(minter, address(rewardDistributor));
    }

    /***************************************
     *          Test: setOperator          *
     ***************************************/

    function testCannotSetOperatorByOther() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rewardDistributor.setOperator(user, true);
    }

    event SetOperator(address operator, bool enable);

    function testSetOperator() public {
        vm.expectEmit(true, true, true, true);
        emit SetOperator(user, true);
        rewardDistributor.setOperator(user, true);
        assertTrue(rewardDistributor.isOperator(user));
    }

    /*******************************************
     *          Test: setMiningFactor          *
     *******************************************/

    function testCannotSetMiningFactorByOther() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rewardDistributor.setMiningFactor(100);
    }

    function testCannotSetMiningFactorGreaterThan100() public {
        vm.expectRevert("incorrect mining factor");
        rewardDistributor.setMiningFactor(128);
    }

    event SetMiningFactor(uint8 miningFactor);

    function testSetMiningFactor() public {
        uint8 newMiningFactor = 10;

        vm.expectEmit(true, true, true, true);
        emit SetMiningFactor(newMiningFactor);
        rewardDistributor.setMiningFactor(newMiningFactor);

        assertEq(uint256(rewardDistributor.miningFactor()), newMiningFactor);
    }

    /***************************************
     *          Test: setTreasury          *
     ***************************************/

    function testCannotSetTreasuryByOther() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rewardDistributor.setTreasury(user);
    }

    event SetTreasury(address treasury);

    function testSetTreasury() public {
        vm.expectEmit(true, true, true, true);
        emit SetTreasury(user);
        rewardDistributor.setTreasury(user);
        assertEq(rewardDistributor.treasury(), user);
    }

    /*****************************************
     *          Test: setLonStaking          *
     *****************************************/

    function testCannotSetLonStakingByOther() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rewardDistributor.setLonStaking(address(lon));
    }

    function testCannotSetLonStakingToNonContract() public {
        vm.expectRevert("Lon staking is not a contract");
        rewardDistributor.setLonStaking(user);
    }

    event SetLonStaking(address lonStaking);

    function testSetLonStaking() public {
        address newLonStaking = address(lon);

        vm.expectEmit(true, true, true, true);
        emit SetLonStaking(newLonStaking);
        rewardDistributor.setLonStaking(newLonStaking);

        assertEq(rewardDistributor.lonStaking(), newLonStaking);
    }

    /*********************************************
     *          Test: setMiningTreasury          *
     *********************************************/

    function testCannotSetMiningTreasury() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rewardDistributor.setMiningTreasury(user);
    }

    event SetMiningTreasury(address miningTreasury);

    function testSetMiningTreasury() public {
        vm.expectEmit(true, true, true, true);
        emit SetMiningTreasury(user);
        rewardDistributor.setMiningTreasury(user);
        assertEq(rewardDistributor.miningTreasury(), user);
    }

    /************************************************
     *          Test: setFeeTokenRecipient          *
     ************************************************/

    function testCannotSetFeeTokenRecipient() public {
        vm.expectRevert("not owner");
        vm.prank(user);
        rewardDistributor.setFeeTokenRecipient(user);
    }

    event SetFeeTokenRecipient(address feeTokenRecipient);

    function testSetFeeTokenRecipient() public {
        vm.expectEmit(true, true, true, true);
        emit SetFeeTokenRecipient(user);
        rewardDistributor.setFeeTokenRecipient(user);
        assertEq(rewardDistributor.feeTokenRecipient(), user);
    }

    /****************************************
     *          Test: recoverERC20          *
     ****************************************/

    function testCannotRecoverERC20ByOther() public {
        vm.expectRevert("only operator or owner can call");
        vm.prank(user);
        rewardDistributor.recoverERC20(address(lon), 100);
    }

    event Recovered(address token, uint256 amount);

    function testRecoverERC20() public {
        uint256 recoverAmount = 100;

        deal(address(lon), address(rewardDistributor), recoverAmount, true);

        BalanceSnapshot.Snapshot memory ownerLon = BalanceSnapshot.take(address(this), address(lon));

        vm.expectEmit(true, true, true, true);
        emit Recovered(address(lon), recoverAmount);
        rewardDistributor.recoverERC20(address(lon), recoverAmount);

        ownerLon.assertChange(int256(recoverAmount));
    }

    /**********************************************
     *          Test: setBuybackInterval          *
     **********************************************/

    function testCannotSetBuyBackIntervalByOther() public {
        vm.expectRevert("only operator or owner can call");
        vm.prank(user);
        rewardDistributor.setBuybackInterval(86400);
    }

    event SetBuybackInterval(uint256 interval);

    function testSetBuybackInterval() public {
        uint32 newBuybackInterval = 86400;
        vm.expectEmit(true, true, true, true);
        emit SetBuybackInterval(newBuybackInterval);
        rewardDistributor.setBuybackInterval(newBuybackInterval);
    }

    /********************************************
     *          Test: setStrategyAddrs          *
     ********************************************/

    function testCannotSetStrategyAddrsByOther() public {
        address[] memory strategyAddrs = new address[](1);
        strategyAddrs[0] = address(new MockStrategy());

        vm.expectRevert("only operator or owner can call");
        vm.prank(user);
        _setStrategyAddrs(strategyAddrs);
    }

    function testCannotSetStrategyAddrsWhenParamsLengthNotMatched() public {
        uint256[] memory indexes = new uint256[](0);
        address[] memory strategyAddrs = new address[](1);
        strategyAddrs[0] = address(new MockStrategy());

        vm.expectRevert("input not the same length");
        rewardDistributor.setStrategyAddrs(indexes, strategyAddrs);
    }

    function testCannotSetStrategyAddrsToNonContractAddr() public {
        address[] memory strategyAddrs = new address[](1);
        strategyAddrs[0] = user;

        vm.expectRevert("strategy is not a contract");
        _setStrategyAddrs(strategyAddrs);
    }

    event SetStrategy(uint256 index, address strategy);

    function testSetStrategyAddrs() public {
        address[] memory strategyAddrs = new address[](2);
        strategyAddrs[0] = address(new MockStrategy());
        strategyAddrs[1] = address(new MockStrategy());

        vm.expectEmit(true, true, true, true);
        emit SetStrategy(0, strategyAddrs[0]);

        vm.expectEmit(true, true, true, true);
        emit SetStrategy(1, strategyAddrs[1]);

        _setStrategyAddrs(strategyAddrs);

        assertEq(rewardDistributor.strategyAddrs(0), strategyAddrs[0]);
        assertEq(rewardDistributor.strategyAddrs(1), strategyAddrs[1]);
    }

    function _setStrategyAddrs(address[] memory strategyAddrs) internal {
        uint256[] memory indexes = new uint256[](strategyAddrs.length);
        for (uint256 i = 0; i < strategyAddrs.length; i++) {
            indexes[i] = i;
        }
        rewardDistributor.setStrategyAddrs(indexes, strategyAddrs);
    }

    /***************************************
     *          Test: setFeeToken          *
     ***************************************/

    function testCannotSetFeeTokenByOther() public {
        vm.expectRevert("only operator or owner can call");
        vm.prank(user);
        _setFeeToken(USDT_FEE_TOKEN);
    }

    function testCannotSetFeeTokenWithInvalidParams() public {
        // feeTokenAddr should be contract
        SetFeeTokenParams memory invalidFeeTokenAddrFeeToken = USDT_FEE_TOKEN;
        invalidFeeTokenAddrFeeToken.feeTokenAddr = user;
        vm.expectRevert("fee token is not a contract");
        _setFeeToken(invalidFeeTokenAddrFeeToken);

        // LFactor <= 100
        SetFeeTokenParams memory invalidLFactorFeeToken = USDT_FEE_TOKEN;
        invalidLFactorFeeToken.LFactor = 255;
        vm.expectRevert("incorrect LFactor");
        _setFeeToken(invalidLFactorFeeToken);

        // RFactor <= 100
        SetFeeTokenParams memory invalidRFactorFeeToken = USDT_FEE_TOKEN;
        invalidRFactorFeeToken.RFactor = 255;
        vm.expectRevert("incorrect RFactor");
        _setFeeToken(invalidRFactorFeeToken);

        // minBuy <= maxBuy
        SetFeeTokenParams memory invalidMinMaxBuyFeeToken = USDT_FEE_TOKEN;
        invalidMinMaxBuyFeeToken.minBuy = 100;
        invalidMinMaxBuyFeeToken.maxBuy = 10;
        vm.expectRevert("incorrect minBuy and maxBuy");
        _setFeeToken(invalidMinMaxBuyFeeToken);
    }

    /* UniswapV2 */

    function testCannotSetFeeTokenWithInvalidUniswapV2Route() public {
        // Should contain at least two tokens in path
        address[] memory path = new address[](1);
        path[0] = address(usdt);

        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.path = path;

        vm.expectRevert("invalid swap path");
        _setFeeToken(feeToken);
    }

    function testSetFeeTokenWithUniswapV2Route() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;

        _expectFeeTokenSetEvents(feeToken);
        _setFeeToken(feeToken);

        _assertFeeTokenSet(feeToken);
    }

    /* Sushiswap */

    function testCannotSetFeeTokenWithInvalidSushiswapRoute() public {
        // Should contain at least two tokens in path
        address[] memory path = new address[](1);
        path[0] = address(usdt);

        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.exchangeIndex = SUSHISWAP_EXCHANGE_INDEX;
        feeToken.path = path;

        vm.expectRevert("invalid swap path");
        _setFeeToken(feeToken);
    }

    function testSetFeeTokenWithSushiswapRoute() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;

        _expectFeeTokenSetEvents(feeToken);
        _setFeeToken(feeToken);

        _assertFeeTokenSet(feeToken);
    }

    function _setFeeToken(SetFeeTokenParams memory params) internal {
        rewardDistributor.setFeeToken(
            params.feeTokenAddr,
            params.exchangeIndex,
            params.path,
            params.LFactor,
            params.RFactor,
            params.enable,
            params.minBuy,
            params.maxBuy
        );
    }

    event EnableFeeToken(address feeToken, bool enable);
    event SetFeeToken(address feeToken, uint256 exchangeIndex, address[] path, uint256 LFactor, uint256 RFactor, uint256 minBuy, uint256 maxBuy);

    function _expectFeeTokenSetEvents(SetFeeTokenParams memory params) internal {
        vm.expectEmit(true, true, true, true);
        emit EnableFeeToken(params.feeTokenAddr, params.enable);
        vm.expectEmit(true, true, true, true);
        emit SetFeeToken(params.feeTokenAddr, params.exchangeIndex, params.path, params.LFactor, params.RFactor, params.minBuy, params.maxBuy);
    }

    function _assertFeeTokenSet(SetFeeTokenParams memory feeToken) internal {
        (uint8 exchangeIndex, uint8 LFactor, uint8 RFactor, , bool enable, uint256 minBuy, uint256 maxBuy) = rewardDistributor.feeTokens(feeToken.feeTokenAddr);
        address[] memory path = rewardDistributor.getFeeTokenPath(feeToken.feeTokenAddr);
        assertEq(uint256(feeToken.exchangeIndex), exchangeIndex);
        assertEq(uint256(feeToken.LFactor), LFactor);
        assertEq(uint256(feeToken.RFactor), RFactor);
        assertEq(feeToken.enable, enable);
        assertEq(feeToken.minBuy, minBuy);
        assertEq(feeToken.maxBuy, maxBuy);
        for (uint256 i = 0; i < feeToken.path.length; i++) {
            assertEq(feeToken.path[i], path[i]);
        }
    }

    /****************************************
     *          Test: setFeeTokens          *
     ****************************************/

    function testCannotSetFeeTokensByOther() public {
        SetFeeTokenParams[] memory feeTokens = new SetFeeTokenParams[](2);
        feeTokens[1] = LON_FEE_TOKEN;
        feeTokens[0] = USDT_FEE_TOKEN;

        vm.expectRevert("only operator or owner can call");
        vm.prank(user);
        _setFeeTokens(feeTokens);
    }

    event SetFeeTokenFailure(address feeToken, string reason, bytes lowLevelData);

    function testSetFeeTokensEmitEventForFailure() public {
        SetFeeTokenParams memory invalidFeeToken = USDT_FEE_TOKEN;
        invalidFeeToken.path = new address[](0);
        SetFeeTokenParams memory validFeeToken = LON_FEE_TOKEN;

        SetFeeTokenParams[] memory feeTokens = new SetFeeTokenParams[](2);
        feeTokens[0] = invalidFeeToken;
        feeTokens[1] = validFeeToken;

        // First fee token will fail to be set
        vm.expectEmit(true, true, true, true);
        emit SetFeeTokenFailure(invalidFeeToken.feeTokenAddr, "invalid swap path", bytes(""));

        // Second fee token will be set
        _expectFeeTokenSetEvents(validFeeToken);

        _setFeeTokens(feeTokens);

        // First fee token will fail to be set
        SetFeeTokenParams memory emptyFeeToken;
        emptyFeeToken.feeTokenAddr = invalidFeeToken.feeTokenAddr;
        _assertFeeTokenSet(emptyFeeToken);

        // Second fee token will be set
        _assertFeeTokenSet(validFeeToken);
    }

    function _setFeeTokens(SetFeeTokenParams[] memory feeTokens) internal {
        address[] memory feeTokenAddrs = new address[](feeTokens.length);
        uint8[] memory exchangeIndexes = new uint8[](feeTokens.length);
        address[][] memory paths = new address[][](feeTokens.length);
        uint8[] memory LFactors = new uint8[](feeTokens.length);
        uint8[] memory RFactors = new uint8[](feeTokens.length);
        bool[] memory enables = new bool[](feeTokens.length);
        uint256[] memory minBuys = new uint256[](feeTokens.length);
        uint256[] memory maxBuys = new uint256[](feeTokens.length);

        for (uint256 i = 0; i < feeTokens.length; i++) {
            SetFeeTokenParams memory feeToken = feeTokens[i];
            feeTokenAddrs[i] = feeToken.feeTokenAddr;
            exchangeIndexes[i] = feeToken.exchangeIndex;
            paths[i] = feeToken.path;
            LFactors[i] = feeToken.LFactor;
            RFactors[i] = feeToken.RFactor;
            enables[i] = feeToken.enable;
            minBuys[i] = feeToken.minBuy;
            maxBuys[i] = feeToken.maxBuy;
        }
        rewardDistributor.setFeeTokens(feeTokenAddrs, exchangeIndexes, paths, LFactors, RFactors, enables, minBuys, maxBuys);
    }

    /******************************************
     *          Test: enableFeeToken          *
     ******************************************/

    function testCannotEnableFeeTokenByOther() public {
        vm.expectRevert("only operator or owner can call");
        vm.prank(user);
        rewardDistributor.enableFeeToken(address(usdt), true);
    }

    function testEnableFeeToken() public {
        vm.expectEmit(true, true, true, true);
        emit EnableFeeToken(address(usdt), true);
        rewardDistributor.enableFeeToken(address(usdt), true);

        _assertFeeTokenEnabled(address(usdt));
    }

    function _assertFeeTokenEnabled(address feeTokenAddr) internal {
        (, , , , bool enable, , ) = rewardDistributor.feeTokens(feeTokenAddr);
        assertTrue(enable);
    }

    /*******************************************
     *          Test: enableFeeTokens          *
     *******************************************/

    function testCannotEnableFeeTokensByOther() public {
        address[] memory feeTokenAddrs = new address[](1);
        feeTokenAddrs[0] = address(usdt);

        bool[] memory enables = new bool[](1);
        enables[0] = true;

        vm.expectRevert("only operator or owner can call");
        vm.prank(user);
        rewardDistributor.enableFeeTokens(feeTokenAddrs, enables);
    }

    function testCannotEnableFeeTokensWhenParamsLengthNotMatched() public {
        address[] memory feeTokenAddrs = new address[](2);
        feeTokenAddrs[0] = address(usdt);
        feeTokenAddrs[1] = address(lon);

        bool[] memory enables = new bool[](1);
        enables[0] = true;

        vm.expectRevert("input not the same length");
        rewardDistributor.enableFeeTokens(feeTokenAddrs, enables);
    }

    function testEnableFeeTokens() public {
        address[] memory feeTokenAddrs = new address[](2);
        feeTokenAddrs[0] = address(lon);
        feeTokenAddrs[1] = address(usdt);

        bool[] memory enables = new bool[](2);
        enables[0] = true;
        enables[1] = true;

        rewardDistributor.enableFeeTokens(feeTokenAddrs, enables);

        _assertFeeTokenEnabled(feeTokenAddrs[0]);
        _assertFeeTokenEnabled(feeTokenAddrs[1]);
    }

    /***********************************
     *          Test: buyback          *
     ***********************************/

    function testCannotBuybackByNotEOA() public {
        vm.expectRevert("only EOA can call");
        // Call directly by testing contract
        rewardDistributor.buyback(address(usdt), 100, 0);
    }

    function testCannotBuybackNonEnabledFeeToken() public {
        vm.expectRevert("fee token is not enabled");
        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), 100, 0);
    }

    function testCannotBuybackMoreThanMaxBuy() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        _setFeeToken(feeToken);

        // Max buy limits buyback swap amount, which is buyback amount * (1- LFactor)
        uint256 buybackToSwap = feeToken.maxBuy + 1;
        uint256 buybackAmount = buybackToSwap.mul(100).div(100 - feeToken.LFactor);

        vm.expectRevert("amount greater than max buy");
        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, 0);
    }

    function testCannotBuybackLessThanMinBuy() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        _setFeeToken(feeToken);

        // Min buy limits buyback swap amount, which is buyback amount * (1- LFactor)
        uint256 buybackToSwap = feeToken.minBuy - 1;
        uint256 buybackAmount = buybackToSwap.mul(100).div(100 - feeToken.LFactor);

        vm.expectRevert("amount less than min buy");
        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, 0);
    }

    function testCannotBuybackTooFrequently() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;

        vm.startPrank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, 0);
        vm.expectRevert("already a buyback recently");
        rewardDistributor.buyback(address(usdt), buybackAmount, 0);
        vm.stopPrank();
    }

    function testCannotBuybackWhenStrategyBalanceNotEnough() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        _setFeeToken(feeToken);

        // This buyback amount will be more than sum of strategies' balance,
        // and will be less than max buy after multiplied by LFactor
        uint256 buybackAmount = feeToken.maxBuy + 1;

        vm.expectRevert("insufficient amount of fee tokens");
        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, 0);
    }

    event BuyBack(address feeToken, uint256 feeTokenAmount, uint256 swappedLonAmount, uint256 LFactor, uint256 RFactor, uint256 minBuy, uint256 maxBuy);
    event DistributeLon(uint256 treasuryAmount, uint256 lonStakingAmount);
    event MintLon(uint256 mintedAmount);

    /* UniswapV2 */

    function testCannotBuybackWhenLONBuybackNotEnoughFromUniswapV2() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = uniswapV2.getAmountsOut(buybackToSwap, USDT_FEE_TOKEN_PATH);
        uint256 lonOut = outs[USDT_FEE_TOKEN_PATH.length - 1];

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, lonOut + 1);
    }

    function testBuyBackFromUniswapV2() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (uint256 buybackToFeeRecipient, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = uniswapV2.getAmountsOut(buybackToSwap, USDT_FEE_TOKEN_PATH);
        uint256 lonOut = outs[USDT_FEE_TOKEN_PATH.length - 1];
        (uint256 lonToTreasury, uint256 lonToStaking, uint256 lonToMiningTreasury) = _splitBuybackLON(feeToken, lonOut);

        BalanceSnapshot.Snapshot memory feeTokenRecipientUSDT = BalanceSnapshot.take(feeTokenRecipient, address(usdt));
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory treasuryLON = BalanceSnapshot.take(treasury, address(lon));
        BalanceSnapshot.Snapshot memory miningTreasuryLON = BalanceSnapshot.take(miningTreasury, address(lon));

        _expectBuybackEvent(feeToken, buybackToSwap, lonOut);

        vm.expectEmit(true, true, true, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(true, true, true, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, lonOut);

        _assertFeeTokenLastTimeBuybackUpdated(address(usdt));

        feeTokenRecipientUSDT.assertChange(int256(buybackToFeeRecipient));
        lonStakingLON.assertChange(int256(lonToStaking));
        treasuryLON.assertChange(int256(lonToTreasury));
        miningTreasuryLON.assertChange(int256(lonToMiningTreasury));
    }

    /* Sushiswap */

    function testCannotBuybackWhenLONBuybackNotEnoughFromSushiswap() public {
        SetFeeTokenParams memory feeToken = CRV_FEE_TOKEN;
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = sushiswap.getAmountsOut(buybackToSwap, CRV_FEE_TOKEN_PATH);
        uint256 lonOut = outs[CRV_FEE_TOKEN_PATH.length - 1];

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        vm.prank(user, user);
        rewardDistributor.buyback(address(crv), buybackAmount, lonOut + 1);
    }

    function testBuybackFromSushiswap() public {
        SetFeeTokenParams memory feeToken = CRV_FEE_TOKEN;
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (uint256 buybackToFeeRecipient, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = sushiswap.getAmountsOut(buybackToSwap, CRV_FEE_TOKEN_PATH);
        uint256 lonOut = outs[CRV_FEE_TOKEN_PATH.length - 1];
        (uint256 lonToTreasury, uint256 lonToStaking, uint256 lonToMiningTreasury) = _splitBuybackLON(feeToken, lonOut);

        BalanceSnapshot.Snapshot memory feeTokenRecipientCRV = BalanceSnapshot.take(feeTokenRecipient, address(crv));
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory treasuryLON = BalanceSnapshot.take(treasury, address(lon));
        BalanceSnapshot.Snapshot memory miningTreasuryLON = BalanceSnapshot.take(miningTreasury, address(lon));

        _expectBuybackEvent(feeToken, buybackToSwap, lonOut);

        vm.expectEmit(true, true, true, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(true, true, true, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.buyback(address(crv), buybackAmount, lonOut);

        _assertFeeTokenLastTimeBuybackUpdated(address(crv));

        feeTokenRecipientCRV.assertChange(int256(buybackToFeeRecipient));
        lonStakingLON.assertChange(int256(lonToStaking));
        treasuryLON.assertChange(int256(lonToTreasury));
        miningTreasuryLON.assertChange(int256(lonToMiningTreasury));
    }

    /* LON */

    function testBuybackLON() public {
        SetFeeTokenParams memory feeToken = LON_FEE_TOKEN;
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (uint256 lonToTreasury, uint256 lonToStaking, uint256 lonToMiningTreasury) = _splitBuybackLON(feeToken, buybackAmount);

        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory treasuryLON = BalanceSnapshot.take(treasury, address(lon));
        BalanceSnapshot.Snapshot memory miningTreasuryLON = BalanceSnapshot.take(miningTreasury, address(lon));

        vm.expectEmit(true, true, true, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(true, true, true, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.buyback(address(lon), buybackAmount, buybackAmount);

        _assertFeeTokenLastTimeBuybackUpdated(address(lon));

        lonStakingLON.assertChange(int256(lonToStaking));
        treasuryLON.assertChange(int256(lonToTreasury));
        miningTreasuryLON.assertChange(int256(lonToMiningTreasury));
    }

    function _splitBuyback(SetFeeTokenParams memory feeToken, uint256 buybackAmount)
        internal
        pure
        returns (uint256 buybackToFeeRecipient, uint256 buybackToSwap)
    {
        buybackToFeeRecipient = buybackAmount.mul(feeToken.LFactor).div(100);
        buybackToSwap = buybackAmount.sub(buybackToFeeRecipient);
    }

    function _splitBuybackLON(SetFeeTokenParams memory feeToken, uint256 lonAmount)
        internal
        view
        returns (
            uint256 lonToTreasury,
            uint256 lonToStaking,
            uint256 lonToMiningTreasury
        )
    {
        lonToTreasury = lonAmount.mul(feeToken.RFactor).div(100);
        lonToStaking = lonAmount.sub(lonToTreasury);
        lonToMiningTreasury = lonAmount.mul(rewardDistributor.miningFactor()).div(100);
    }

    function _expectBuybackEvent(
        SetFeeTokenParams memory feeToken,
        uint256 swapAmount,
        uint256 lonAmount
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit BuyBack(feeToken.feeTokenAddr, swapAmount, lonAmount, feeToken.LFactor, feeToken.RFactor, feeToken.minBuy, feeToken.maxBuy);
    }

    function _assertFeeTokenLastTimeBuybackUpdated(address feeTokenAddr) internal {
        (, , , uint32 lastTimeBuyback, , , ) = rewardDistributor.feeTokens(feeTokenAddr);
        assertEq(lastTimeBuyback, block.timestamp);
    }

    /****************************************
     *          Test: batchBuyback          *
     ****************************************/

    function testCannotBuybackWithInvalidParams() public {
        address[] memory feeTokenAddrs = new address[](2);
        feeTokenAddrs[0] = address(lon);
        feeTokenAddrs[1] = address(usdt);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        uint256[] memory minLonAmounts = new uint256[](1);
        minLonAmounts[0] = 0;

        vm.expectRevert("input not the same length");
        vm.prank(user, user);
        rewardDistributor.batchBuyback(feeTokenAddrs, amounts, minLonAmounts);
    }

    event BuyBackFailure(address feeToken, uint256 feeTokenAmount, string reason, bytes lowLevelData);

    function testBatchBuybackEmitEventForFailure() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        _setFeeToken(feeToken);

        address[] memory feeTokenAddrs = new address[](2);
        feeTokenAddrs[0] = address(lon); // Unenabled
        feeTokenAddrs[1] = feeToken.feeTokenAddr; // Enabled

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = LON_FEE_TOKEN.maxBuy;
        amounts[1] = feeToken.maxBuy;

        uint256[] memory minLonAmounts = new uint256[](2);
        minLonAmounts[0] = 0;
        minLonAmounts[1] = 0;

        uint256 buybackAmount = amounts[1];
        (, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = uniswapV2.getAmountsOut(buybackToSwap, USDT_FEE_TOKEN_PATH);
        uint256 lonOut = outs[USDT_FEE_TOKEN_PATH.length - 1];
        (uint256 lonToTreasury, uint256 lonToStaking, uint256 lonToMiningTreasury) = _splitBuybackLON(feeToken, lonOut);

        // First buyback will fail
        vm.expectEmit(true, true, true, true);
        emit BuyBackFailure(address(lon), LON_FEE_TOKEN.maxBuy, "fee token is not enabled", bytes(""));

        // Second buyback will succeed
        _expectBuybackEvent(feeToken, buybackToSwap, lonOut);

        vm.expectEmit(true, true, true, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(true, true, true, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.batchBuyback(feeTokenAddrs, amounts, minLonAmounts);
    }
}
