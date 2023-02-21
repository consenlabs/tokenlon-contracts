// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "contracts/AMMStrategy.sol";
import "test/utils/BalanceUtil.sol";
import "test/utils/Tokens.sol";

contract TestAMMStrategy is Tokens, BalanceUtil {
    using SafeERC20 for IERC20;

    address entryPoint = makeAddr("entryPoint");
    address owner = makeAddr("owner");
    address[] wallets = [entryPoint, owner];
    address[] amms = [address(SUSHISWAP_ADDRESS), UNISWAP_V2_ADDRESS, UNISWAP_V3_ADDRESS, BALANCER_V2_ADDRESS, CURVE_USDT_POOL_ADDRESS];
    address[] assets = [address(WETH_ADDRESS), USDT_ADDRESS, USDC_ADDRESS, DAI_ADDRESS, WBTC_ADDRESS, LON_ADDRESS, ANKRETH_ADDRESS];

    AMMStrategy ammStrategy;

    uint256 DEADLINE = block.timestamp + 1;
    address[] DEFAULT_Single_HOP_PATH;
    address[] DEFAULT_MULTI_HOP_PATH;

    // effectively a "beforeEach" block
    function setUp() public {
        dealWallets(100);
        ammStrategy = new AMMStrategy(entryPoint, amms);
        ammStrategy.approveAssets(assets, amms, type(uint256).max);
        ammStrategy.transferOwnership(owner);
        // Set token balance and approve
        for (uint256 i = 0; i < tokens.length; ++i) {
            setERC20Balance(address(assets[i]), entryPoint, uint256(100));
        }

        // Label addresses for easier debugging
        vm.label(owner, "Owner");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammStrategy), "AMMStrategyContract");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(UNISWAP_V3_ADDRESS, "UniswapV3");
        vm.label(BALANCER_V2_ADDRESS, "BalancerV2");
        vm.label(CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
    }

    /*********************************
     *          Test Helpers         *
     *********************************/
    function dealWallets(uint256 amount) internal {
        // Deal 100 ETH to each account
        for (uint256 i = 0; i < wallets.length; i++) {
            deal(wallets[i], amount);
        }
    }

    // function _genTradePayload(AMMStrategyEntry memory entry)
    //     internal
    //     pure
    //     returns (
    //         address srcToken,
    //         uint256 inputAmount,
    //         bytes memory data
    //     )
    // {
    //     srcToken = entry.takerAssetAddr;
    //     inputAmount = entry.takerAssetAmount;
    //     data = abi.encode(entry.makerAddr, entry.makerAssetAddr, entry.makerSpecificData, entry.path, entry.deadline);
    // }

    function _sendTakerAssetFromEntryPoint(address takerAssetAddr, uint256 takerAssetAmount) internal {
        vm.prank(entryPoint);
        IERC20(takerAssetAddr).safeTransfer(address(ammStrategy), takerAssetAmount);
        vm.stopPrank();
    }
}
