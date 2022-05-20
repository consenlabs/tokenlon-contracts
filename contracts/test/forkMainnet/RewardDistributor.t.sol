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
import "contracts-test/utils/BalanceUtil.sol";
import "contracts-test/utils/UniswapV3Util.sol";

contract RewardDistributorTest is Test, BalanceUtil {
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

    IUniswapRouterV2 uniswapV2 = IUniswapRouterV2(Addresses.UNISWAP_V2_ADDRESS);
    IUniswapRouterV2 sushiswap = IUniswapRouterV2(Addresses.SUSHISWAP_ADDRESS);
    IUniswapRouterV3 uniswapV3 = IUniswapRouterV3(Addresses.UNISWAP_V3_ADDRESS);
    IUniswapV3Quoter uniswapV3Quoter = IUniswapV3Quoter(Addresses.UNISWAP_V3_QUOTER_ADDRESS);

    Lon lon = Lon(Addresses.LON_ADDRESS);
    IERC20 usdt = IERC20(Addresses.USDT_ADDRESS);

    MockStrategy[] strategies = [new MockStrategy(), new MockStrategy()];
    MockContract lonStaking = new MockContract();
    RewardDistributor rewardDistributor;

    struct SetFeeTokenParams {
        address feeTokenAddr;
        bytes encodedAMMRoute;
        uint8 LFactor;
        uint8 RFactor;
        bool enable;
        uint256 minBuy;
        uint256 maxBuy;
    }

    address[] LON_FEE_TOKEN_PATH = [address(lon), address(lon)];
    SetFeeTokenParams LON_FEE_TOKEN =
        SetFeeTokenParams({
            feeTokenAddr: address(lon),
            encodedAMMRoute: _encodeUniswapV2Route(LON_FEE_TOKEN_PATH),
            LFactor: 0,
            RFactor: 40,
            enable: true,
            minBuy: 10,
            maxBuy: 100
        });

    address[] USDT_FEE_TOKEN_PATH = [address(usdt), Addresses.WETH_ADDRESS, address(lon)];
    uint24[] USDT_POOL_FEES = [FEE_MEDIUM, FEE_MEDIUM];
    SetFeeTokenParams USDT_FEE_TOKEN =
        SetFeeTokenParams({
            feeTokenAddr: address(usdt),
            encodedAMMRoute: _encodeUniswapV2Route(USDT_FEE_TOKEN_PATH),
            LFactor: 20,
            RFactor: 40,
            enable: true,
            minBuy: 10,
            maxBuy: 100
        });

    function setUp() public {
        rewardDistributor = new RewardDistributor(
            RewardDistributor.ConstructorParams(
                address(lon),
                Addresses.SUSHISWAP_ADDRESS,
                Addresses.UNISWAP_V2_ADDRESS,
                Addresses.UNISWAP_V3_ADDRESS,
                // Use this testing contract as owner and operator
                address(this), // owner
                address(this), // operator
                MIN_BUYBACK_INTERVAL,
                BUYBACK_INTERVAL,
                MINING_FACTOR,
                treasury,
                address(lonStaking),
                miningTreasury,
                feeTokenRecipient
            )
        );
        address[] memory strategyAddrs = new address[](strategies.length);
        // Balance of strategies will sum up to max buy of fee tokens
        for (uint256 i = 0; i < strategies.length; i++) {
            MockStrategy strategy = strategies[i];
            strategyAddrs[i] = address(strategy);
            vm.startPrank(address(strategy));
            // LON
            setERC20BalanceRaw(address(lon), address(strategy), LON_FEE_TOKEN.maxBuy / strategies.length);
            IERC20(lon).safeApprove(address(rewardDistributor), type(uint256).max);
            // USDT
            setERC20BalanceRaw(address(usdt), address(strategy), USDT_FEE_TOKEN.maxBuy / strategies.length);
            usdt.safeApprove(address(rewardDistributor), type(uint256).max);
            vm.stopPrank();
        }
        _setStrategyAddrs(strategyAddrs);

        vm.prank(lon.owner());
        lon.setMinter(address(rewardDistributor));

        // Deal 100 ETH to user
        vm.deal(user, 100 ether);

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
        vm.expectEmit(false, false, false, true);
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

        vm.expectEmit(false, false, false, true);
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
        vm.expectEmit(false, false, false, true);
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

        vm.expectEmit(false, false, false, true);
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
        vm.expectEmit(false, false, false, true);
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
        vm.expectEmit(false, false, false, true);
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

        setERC20BalanceRaw(address(lon), address(rewardDistributor), recoverAmount);

        BalanceSnapshot.Snapshot memory ownerLon = BalanceSnapshot.take(address(this), address(lon));

        vm.expectEmit(false, false, false, true);
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
        vm.expectEmit(false, false, false, true);
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

        vm.expectEmit(false, false, false, true);
        emit SetStrategy(0, strategyAddrs[0]);

        vm.expectEmit(false, false, false, true);
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
        feeToken.encodedAMMRoute = _encodeUniswapV2Route(path);

        vm.expectRevert("invalid Sushiswap/Uniswap v2 swap path");
        _setFeeToken(feeToken);
    }

    function testSetFeeTokenWithUniswapV2Route() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeUniswapV2Route(USDT_FEE_TOKEN_PATH);

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
        feeToken.encodedAMMRoute = _encodeSushiswapRoute(path);

        vm.expectRevert("invalid Sushiswap/Uniswap v2 swap path");
        _setFeeToken(feeToken);
    }

    function testSetFeeTokenWithSushiswapRoute() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeSushiswapRoute(USDT_FEE_TOKEN_PATH);

        _expectFeeTokenSetEvents(feeToken);
        _setFeeToken(feeToken);

        _assertFeeTokenSet(feeToken);
    }

    /* UniswapV3 */

    function testCannotSetFeeTokenWithInvalidUniswapV3Route() public {
        // Should contain at least two pools in path
        address[] memory path = new address[](1);
        path[0] = address(usdt);

        uint24[] memory fees = new uint24[](0);

        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeUniswapV3Route(path, fees);

        vm.expectRevert("invalid Uniswap v3 swap path");
        _setFeeToken(feeToken);
    }

    function testSetFeeTokenWithUniswapV3Route() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeUniswapV3Route(USDT_FEE_TOKEN_PATH, USDT_POOL_FEES);

        _expectFeeTokenSetEvents(feeToken);
        _setFeeToken(feeToken);

        _assertFeeTokenSet(feeToken);
    }

    function _encodeUniswapV2Route(address[] memory path) internal returns (bytes memory) {
        return abi.encode(0, path);
    }

    function _encodeSushiswapRoute(address[] memory path) internal returns (bytes memory) {
        return abi.encode(1, path);
    }

    function _encodeUniswapV3Route(address[] memory path, uint24[] memory fees) internal returns (bytes memory) {
        return abi.encode(2, encodePath(path, fees));
    }

    function _setFeeToken(SetFeeTokenParams memory params) internal {
        rewardDistributor.setFeeToken(params.feeTokenAddr, params.encodedAMMRoute, params.LFactor, params.RFactor, params.enable, params.minBuy, params.maxBuy);
    }

    event EnableFeeToken(address feeToken, bool enable);
    event SetFeeToken(address feeToken, bytes encodedAMMRoute, uint256 LFactor, uint256 RFactor, uint256 minBuy, uint256 maxBuy);

    function _expectFeeTokenSetEvents(SetFeeTokenParams memory params) internal {
        vm.expectEmit(false, false, false, true);
        emit EnableFeeToken(params.feeTokenAddr, params.enable);
        vm.expectEmit(false, false, false, true);
        emit SetFeeToken(params.feeTokenAddr, params.encodedAMMRoute, params.LFactor, params.RFactor, params.minBuy, params.maxBuy);
    }

    function _assertFeeTokenSet(SetFeeTokenParams memory feeToken) internal {
        (uint8 LFactor, uint8 RFactor, , bool enable, uint256 minBuy, uint256 maxBuy, bytes memory encodedAMMRoute) = rewardDistributor.feeTokens(
            feeToken.feeTokenAddr
        );
        assertEq(uint256(feeToken.LFactor), LFactor);
        assertEq(uint256(feeToken.RFactor), RFactor);
        assertEq(feeToken.enable, enable);
        assertEq(feeToken.minBuy, minBuy);
        assertEq(feeToken.maxBuy, maxBuy);
        assertEq(feeToken.encodedAMMRoute, encodedAMMRoute);
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
        invalidFeeToken.encodedAMMRoute = _encodeSushiswapRoute(new address[](0));
        SetFeeTokenParams memory validFeeToken = LON_FEE_TOKEN;

        SetFeeTokenParams[] memory feeTokens = new SetFeeTokenParams[](2);
        feeTokens[0] = invalidFeeToken;
        feeTokens[1] = validFeeToken;

        // First fee token will fail to be set
        vm.expectEmit(false, false, false, true);
        emit SetFeeTokenFailure(invalidFeeToken.feeTokenAddr, "invalid Sushiswap/Uniswap v2 swap path", bytes(""));

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
        bytes[] memory encodedAMMRoutes = new bytes[](feeTokens.length);
        uint8[] memory LFactors = new uint8[](feeTokens.length);
        uint8[] memory RFactors = new uint8[](feeTokens.length);
        bool[] memory enables = new bool[](feeTokens.length);
        uint256[] memory minBuys = new uint256[](feeTokens.length);
        uint256[] memory maxBuys = new uint256[](feeTokens.length);

        for (uint256 i = 0; i < feeTokens.length; i++) {
            SetFeeTokenParams memory feeToken = feeTokens[i];
            feeTokenAddrs[i] = feeToken.feeTokenAddr;
            encodedAMMRoutes[i] = feeToken.encodedAMMRoute;
            LFactors[i] = feeToken.LFactor;
            RFactors[i] = feeToken.RFactor;
            enables[i] = feeToken.enable;
            minBuys[i] = feeToken.minBuy;
            maxBuys[i] = feeToken.maxBuy;
        }
        rewardDistributor.setFeeTokens(feeTokenAddrs, encodedAMMRoutes, LFactors, RFactors, enables, minBuys, maxBuys);
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
        vm.expectEmit(false, false, false, true);
        emit EnableFeeToken(address(usdt), true);
        rewardDistributor.enableFeeToken(address(usdt), true);

        _assertFeeTokenEnabled(address(usdt));
    }

    function _assertFeeTokenEnabled(address feeTokenAddr) internal {
        (, , , bool enable, , , ) = rewardDistributor.feeTokens(feeTokenAddr);
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

        vm.expectEmit(false, false, false, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(false, false, false, true);
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
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeSushiswapRoute(USDT_FEE_TOKEN_PATH);
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = sushiswap.getAmountsOut(buybackToSwap, USDT_FEE_TOKEN_PATH);
        uint256 lonOut = outs[USDT_FEE_TOKEN_PATH.length - 1];

        vm.expectRevert("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, lonOut + 1);
    }

    function testBuybackFromSushiswap() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeSushiswapRoute(USDT_FEE_TOKEN_PATH);
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (uint256 buybackToFeeRecipient, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = sushiswap.getAmountsOut(buybackToSwap, USDT_FEE_TOKEN_PATH);
        uint256 lonOut = outs[USDT_FEE_TOKEN_PATH.length - 1];
        (uint256 lonToTreasury, uint256 lonToStaking, uint256 lonToMiningTreasury) = _splitBuybackLON(feeToken, lonOut);

        BalanceSnapshot.Snapshot memory feeTokenRecipientUSDT = BalanceSnapshot.take(feeTokenRecipient, address(usdt));
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory treasuryLON = BalanceSnapshot.take(treasury, address(lon));
        BalanceSnapshot.Snapshot memory miningTreasuryLON = BalanceSnapshot.take(miningTreasury, address(lon));

        _expectBuybackEvent(feeToken, buybackToSwap, lonOut);

        vm.expectEmit(false, false, false, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(false, false, false, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, lonOut);

        _assertFeeTokenLastTimeBuybackUpdated(address(usdt));

        feeTokenRecipientUSDT.assertChange(int256(buybackToFeeRecipient));
        lonStakingLON.assertChange(int256(lonToStaking));
        treasuryLON.assertChange(int256(lonToTreasury));
        miningTreasuryLON.assertChange(int256(lonToMiningTreasury));
    }

    /* UniswapV3 */

    function testCannotBuybackWhenLONBuybackNotEnoughFromUniswapV3() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeUniswapV3Route(USDT_FEE_TOKEN_PATH, USDT_POOL_FEES);
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        bytes memory path = encodePath(USDT_FEE_TOKEN_PATH, USDT_POOL_FEES);
        uint256 lonOut = uniswapV3Quoter.quoteExactInput(path, buybackToSwap);

        vm.expectRevert("Too little received");
        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, lonOut + 1);
    }

    function testBuybackFromUniswapV3() public {
        SetFeeTokenParams memory feeToken = USDT_FEE_TOKEN;
        feeToken.encodedAMMRoute = _encodeUniswapV3Route(USDT_FEE_TOKEN_PATH, USDT_POOL_FEES);
        _setFeeToken(feeToken);

        uint256 buybackAmount = feeToken.maxBuy;
        (uint256 buybackToFeeRecipient, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        bytes memory path = encodePath(USDT_FEE_TOKEN_PATH, USDT_POOL_FEES);
        uint256 lonOut = uniswapV3Quoter.quoteExactInput(path, buybackToSwap);
        (uint256 lonToTreasury, uint256 lonToStaking, uint256 lonToMiningTreasury) = _splitBuybackLON(feeToken, lonOut);

        BalanceSnapshot.Snapshot memory feeTokenRecipientUSDT = BalanceSnapshot.take(feeTokenRecipient, address(usdt));
        BalanceSnapshot.Snapshot memory lonStakingLON = BalanceSnapshot.take(address(lonStaking), address(lon));
        BalanceSnapshot.Snapshot memory treasuryLON = BalanceSnapshot.take(treasury, address(lon));
        BalanceSnapshot.Snapshot memory miningTreasuryLON = BalanceSnapshot.take(miningTreasury, address(lon));

        _expectBuybackEvent(feeToken, buybackToSwap, lonOut);

        vm.expectEmit(false, false, false, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(false, false, false, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.buyback(address(usdt), buybackAmount, lonOut);

        _assertFeeTokenLastTimeBuybackUpdated(address(usdt));

        feeTokenRecipientUSDT.assertChange(int256(buybackToFeeRecipient));
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

        vm.expectEmit(false, false, false, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(false, false, false, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.buyback(address(lon), buybackAmount, buybackAmount);

        _assertFeeTokenLastTimeBuybackUpdated(address(lon));

        lonStakingLON.assertChange(int256(lonToStaking));
        treasuryLON.assertChange(int256(lonToTreasury));
        miningTreasuryLON.assertChange(int256(lonToMiningTreasury));
    }

    function _splitBuyback(SetFeeTokenParams memory feeToken, uint256 buybackAmount) internal returns (uint256 buybackToFeeRecipient, uint256 buybackToSwap) {
        buybackToFeeRecipient = buybackAmount.mul(feeToken.LFactor).div(100);
        buybackToSwap = buybackAmount.sub(buybackToFeeRecipient);
    }

    function _splitBuybackLON(SetFeeTokenParams memory feeToken, uint256 lonAmount)
        internal
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
        vm.expectEmit(false, false, false, true);
        emit BuyBack(feeToken.feeTokenAddr, swapAmount, lonAmount, feeToken.LFactor, feeToken.RFactor, feeToken.minBuy, feeToken.maxBuy);
    }

    function _assertFeeTokenLastTimeBuybackUpdated(address feeTokenAddr) internal {
        (, , uint32 lastTimeBuyback, , , , ) = rewardDistributor.feeTokens(feeTokenAddr);
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
        (uint256 buybackToFeeRecipient, uint256 buybackToSwap) = _splitBuyback(feeToken, buybackAmount);

        uint256[] memory outs = uniswapV2.getAmountsOut(buybackToSwap, USDT_FEE_TOKEN_PATH);
        uint256 lonOut = outs[USDT_FEE_TOKEN_PATH.length - 1];
        (uint256 lonToTreasury, uint256 lonToStaking, uint256 lonToMiningTreasury) = _splitBuybackLON(feeToken, lonOut);

        // First buyback will fail
        vm.expectEmit(false, false, false, true);
        emit BuyBackFailure(address(lon), LON_FEE_TOKEN.maxBuy, "fee token is not enabled", bytes(""));

        // Second buyback will succeed
        _expectBuybackEvent(feeToken, buybackToSwap, lonOut);

        vm.expectEmit(false, false, false, true);
        emit DistributeLon(lonToTreasury, lonToStaking);

        vm.expectEmit(false, false, false, true);
        emit MintLon(lonToMiningTreasury);

        vm.prank(user, user);
        rewardDistributor.batchBuyback(feeTokenAddrs, amounts, minLonAmounts);
    }
}
