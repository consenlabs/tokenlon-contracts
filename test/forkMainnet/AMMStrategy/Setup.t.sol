// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "contracts/AMMStrategy.sol";
import "contracts/AMMQuoter.sol";
import "test/utils/StrategySharedSetup.sol"; // Using the deployment Strategy Contract function
import { getEIP712Hash } from "test/utils/Sig.sol";

contract TestAMMStrategy is StrategySharedSetup {
    using SafeERC20 for IERC20;

    struct AMMStrategyEntry {
        address takerAssetAddr;
        uint256 takerAssetAmount;
        address makerAddr;
        address makerAssetAddr;
        bytes makerSpecificData;
        address[] path;
        uint256 deadline;
    }

    address entryPoint = makeAddr("entryPoint");
    address owner = makeAddr("owner");
    address[] wallet = [entryPoint, owner];

    AMMStrategy ammStrategy;
    AMMQuoter ammQuoter;

    uint256 DEADLINE = block.timestamp + 1;
    address[] DEFAULT_Single_HOP_PATH;
    address[] DEFAULT_MULTI_HOP_PATH;
    AMMStrategyEntry DEFAULT_ENTRY;

    // effectively a "beforeEach" block
    function setUp() public {
        setUpSystemContracts();
        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        tokens = [weth, usdt, dai, ankreth];
        for (uint256 i = 0; i < tokens.length; i++) {
            setERC20Balance(address(tokens[i]), entryPoint, uint256(100));
        }

        // Default order
        DEFAULT_ENTRY = AMMStrategyEntry(
            address(dai), // takerAssetAddr
            uint256(100 * 1e18), // takerAssetAmount
            UNISWAP_V2_ADDRESS, // makerAddr
            address(usdt), // makerAssetAddr
            "", // makerSpecificData;
            DEFAULT_Single_HOP_PATH, // path
            DEADLINE // deadline
        );

        // Label addresses for easier debugging
        vm.label(owner, "Owner");
        vm.label(address(this), "TestingContract");
        vm.label(address(ammQuoter), "AMMQuoterContract");
        vm.label(address(ammStrategy), "AMMStrategyContract");
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(UNISWAP_V3_ADDRESS, "UniswapV3");
        vm.label(CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
        vm.label(CURVE_TRICRYPTO2_POOL_ADDRESS, "CurveTriCryptoPool");
    }

    // Deploy the strategy contract by overriding the StrategySharedSetup.sol deployment function
    function _deployStrategyAndUpgrade() internal override returns (address) {
        ammQuoter = new AMMQuoter(
            UNISWAP_V2_ADDRESS,
            UNISWAP_V3_ADDRESS,
            UNISWAP_V3_QUOTER_ADDRESS,
            SUSHISWAP_ADDRESS,
            BALANCER_V2_ADDRESS,
            IPermanentStorage(permanentStorage),
            address(weth)
        );

        ammStrategy = new AMMStrategy(owner, entryPoint, SUSHISWAP_ADDRESS, UNISWAP_V2_ADDRESS, UNISWAP_V3_ADDRESS, BALANCER_V2_ADDRESS);

        return address(ammStrategy);
    }

    function _setupDeployedStrategy() internal override {
        ammQuoter = AMMQuoter(vm.envAddress("AMMQUOTER_ADDRESS"));
        ammStrategy = AMMStrategy(payable(vm.envAddress("AMMStrategy_ADDRESS")));
        owner = ammStrategy.owner();
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _genTradePayload(AMMStrategyEntry memory entry)
        internal
        pure
        returns (
            address srcToken,
            uint256 inputAmount,
            bytes memory data
        )
    {
        srcToken = entry.takerAssetAddr;
        inputAmount = entry.takerAssetAmount;
        data = abi.encode(entry.makerAddr, entry.makerAssetAddr, entry.makerSpecificData, entry.path, entry.deadline);
    }

    function _sendTakerAssetFromEntryPoint(address takerAssetAddr, uint256 takerAssetAmount) internal {
        vm.prank(entryPoint);
        IERC20(takerAssetAddr).safeTransfer(address(ammStrategy), takerAssetAmount);
        vm.stopPrank();
    }
}
