// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/AMMWrapperWithPath.sol";
import "contracts/interfaces/IPermanentStorage.sol";
import "contracts/utils/AMMLibEIP712.sol";
import "contracts-test/utils/UniswapV3Util.sol";
import "contracts-test/utils/StrategySharedSetup.sol"; // Using the deployment Strategy Contract function
import { getEIP712Hash } from "contracts-test/utils/Sig.sol";
import "contracts/AMMQuoter.sol";

contract TestAMMWrapperWithPath is StrategySharedSetup {
    using SafeERC20 for IERC20;
    uint256 userPrivateKey = uint256(1);
    uint256 otherPrivateKey = uint256(2);

    address user = vm.addr(userPrivateKey);
    address feeCollector = address(0x133701);
    address relayer = address(0x133702);
    address[] wallet = [user, relayer];
    AMMQuoter ammQuoter;
    AMMWrapperWithPath ammWrapperWithPath;
    IERC20 weth = IERC20(WETH_ADDRESS);
    IERC20 usdt = IERC20(USDT_ADDRESS);
    IERC20 usdc = IERC20(USDC_ADDRESS);
    IERC20 dai = IERC20(DAI_ADDRESS);
    IERC20 wbtc = IERC20(WBTC_ADDRESS);
    IERC20 lon = IERC20(LON_ADDRESS);
    IERC20[] tokens = [weth, usdt, usdc, dai, wbtc, lon];

    uint16 DEFAULT_FEE_FACTOR = 500;
    uint256 DEADLINE = block.timestamp + 1;
    AMMLibEIP712.Order DEFAULT_ORDER;
    // UniswapV3
    uint256 UNSUPPORTED_SWAP_TYPE = 0;
    uint256 INVALID_SWAP_TYPE = 3;
    uint256 SINGLE_POOL_SWAP_TYPE = 1;
    uint256 MULTI_POOL_SWAP_TYPE = 2;
    address[] DEFAULT_MULTI_HOP_PATH;
    uint24[] DEFAULT_MULTI_HOP_POOL_FEES;
    // BalancerV2
    bytes32 constant BALANCER_DAI_USDT_USDC_POOL = 0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063;
    bytes32 constant BALANCER_WETH_DAI_POOL = 0x0b09dea16768f0799065c475be02919503cb2a3500020000000000000000001a;
    bytes32 constant BALANCER_WETH_USDC_POOL = 0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019;

    event Swapped(
        string source,
        bytes32 indexed transactionHash,
        address indexed userAddr,
        bool relayed,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );

    // effectively a "beforeEach" block
    function setUp() public virtual {
        // Deploy and Setup Spender, AllowanceTarget, UserProxy, Tokenlon,
        // PermanentStorage, ProxyPermanentStorage, AMMWrapperWithPath contracts
        setUpSystemContracts();
        address[] memory relayerListAddress = new address[](1);
        relayerListAddress[0] = relayer;
        bool[] memory relayerListBool = new bool[](1);
        relayerListBool[0] = true;
        permanentStorage.setRelayersValid(relayerListAddress, relayerListBool);

        // Deal 100 ETH to each account
        dealWallet(wallet, 100 ether);
        // Set token balance and approve
        setEOABalanceAndApprove(user, tokens, uint256(100));

        ammQuoter = new AMMQuoter(IPermanentStorage(permanentStorage), address(weth));

        // Default order
        DEFAULT_ORDER = AMMLibEIP712.Order(
            UNISWAP_V3_ADDRESS, // makerAddr
            address(usdc), // takerAssetAddr
            address(dai), // makerAssetAddr
            uint256(100 * 1e6), // takerAssetAmount
            uint256(90 * 1e18), // makerAssetAmount
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
        vm.label(UNISWAP_V2_ADDRESS, "UniswapV2");
        vm.label(SUSHISWAP_ADDRESS, "Sushiswap");
        vm.label(UNISWAP_V3_ADDRESS, "UniswapV3");
        vm.label(CURVE_USDT_POOL_ADDRESS, "CurveUSDTPool");
        vm.label(CURVE_TRICRYPTO2_POOL_ADDRESS, "CurveTriCryptoPool");
    }

    // Deploy the strategy contract by overriding the StrategySharedSetup.sol deployment function
    function _deployStrategyAndUpgrade() internal override returns (address) {
        ammWrapperWithPath = new AMMWrapperWithPath(
            address(this), // This contract would be the operator
            DEFAULT_FEE_FACTOR,
            address(userProxy),
            ISpender(address(spender)),
            permanentStorage,
            IWETH(address(weth)),
            UNISWAP_V2_ADDRESS,
            SUSHISWAP_ADDRESS,
            UNISWAP_V3_ADDRESS,
            BALANCER_V2_ADDRESS,
            feeCollector
        );
        // Setup
        userProxy.upgradeAMMWrapper(address(ammWrapperWithPath), true);
        permanentStorage.upgradeAMMWrapper(address(ammWrapperWithPath));
        permanentStorage.setPermission(permanentStorage.transactionSeenStorageId(), address(ammWrapperWithPath), true);
        return address(ammWrapperWithPath);
    }

    /*********************************
     *          Test Helpers         *
     *********************************/

    function _signTrade(uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(ammWrapperWithPath.EIP712_DOMAIN_SEPARATOR(), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }

    function _genTradePayload(
        AMMLibEIP712.Order memory order,
        uint256 feeFactor,
        bytes memory sig,
        bytes memory makerSpecificData,
        address[] memory path
    ) internal pure returns (bytes memory payload) {
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
