// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import { Test, Vm } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockWETH } from "test/mocks/MockWETH.sol";

address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
address constant ZERO_ADDRESS = address(0);

contract Addresses is Test {
    IERC20 public weth;
    IERC20 public usdt;
    IERC20 public usdc;
    IERC20 public dai;
    IERC20 public wbtc;
    IERC20 public lon;
    IERC20 public ankreth;
    IERC20[] public tokens;

    string private file = readAddresses(vm);

    // Since token may be newly deployed in local testnet case, these imported addresses may not be the actual ones.
    address private WETH_ADDRESS = abi.decode(vm.parseJson(file, "$.WETH_ADDRESS"), (address));
    address private USDT_ADDRESS = abi.decode(vm.parseJson(file, "$.USDT_ADDRESS"), (address));
    address private USDC_ADDRESS = abi.decode(vm.parseJson(file, "$.USDC_ADDRESS"), (address));
    address private DAI_ADDRESS = abi.decode(vm.parseJson(file, "$.DAI_ADDRESS"), (address));
    address private LON_ADDRESS = abi.decode(vm.parseJson(file, "$.LON_ADDRESS"), (address));
    address private WBTC_ADDRESS = abi.decode(vm.parseJson(file, "$.WBTC_ADDRESS"), (address));
    address private ANKRETH_ADDRESS = abi.decode(vm.parseJson(file, "$.ANKRETH_ADDRESS"), (address));

    address CRV_ADDRESS = abi.decode(vm.parseJson(file, "$.CRV_ADDRESS"), (address));
    address TUSD_ADDRESS = abi.decode(vm.parseJson(file, "$.TUSD_ADDRESS"), (address));

    // Curve coins
    address cDAI_ADDRESS = abi.decode(vm.parseJson(file, "$.cDAI_ADDRESS"), (address));
    address cUSDC_ADDRESS = abi.decode(vm.parseJson(file, "$.cUSDC_ADDRESS"), (address));
    address yDAI_ADDRESS = abi.decode(vm.parseJson(file, "$.yDAI_ADDRESS"), (address));
    address yUSDC_ADDRESS = abi.decode(vm.parseJson(file, "$.yUSDC_ADDRESS"), (address));
    address yUSDT_ADDRESS = abi.decode(vm.parseJson(file, "$.yUSDT_ADDRESS"), (address));
    address yTUSD_ADDRESS = abi.decode(vm.parseJson(file, "$.yTUSD_ADDRESS"), (address));

    address UNISWAP_V2_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V2_ADDRESS"), (address));
    address SUSHISWAP_ADDRESS = abi.decode(vm.parseJson(file, "$.SUSHISWAP_ADDRESS"), (address));
    address UNISWAP_V3_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V3_ADDRESS"), (address));
    address UNISWAP_V3_QUOTER_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V3_QUOTER_ADDRESS"), (address));
    address UNISWAP_PERMIT2_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_PERMIT2_ADDRESS"), (address));
    address CURVE_USDT_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_USDT_POOL_ADDRESS"), (address));
    address CURVE_COMPOUND_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_COMPOUND_POOL_ADDRESS"), (address));
    address CURVE_Y_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_Y_POOL_ADDRESS"), (address));
    address CURVE_3_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_3_POOL_ADDRESS"), (address));
    address CURVE_TRICRYPTO2_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_TRICRYPTO2_POOL_ADDRESS"), (address));
    address CURVE_ANKRETH_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_ANKRETH_POOL_ADDRESS"), (address));
    address BALANCER_V2_ADDRESS = abi.decode(vm.parseJson(file, "$.BALANCER_V2_ADDRESS"), (address));

    address ARBITRUM_L1_GATEWAY_ROUTER_ADDR = abi.decode(vm.parseJson(file, "$.ARBITRUM_L1_GATEWAY_ROUTER_ADDR"), (address));
    address ARBITRUM_L1_BRIDGE_ADDR = abi.decode(vm.parseJson(file, "$.ARBITRUM_L1_BRIDGE_ADDR"), (address));
    address OPTIMISM_L1_STANDARD_BRIDGE_ADDR = abi.decode(vm.parseJson(file, "$.OPTIMISM_L1_STANDARD_BRIDGE_ADDR"), (address));

    constructor() {
        uint256 chainId = getChainId();

        if (chainId == 31337) {
            // local testnet, deploy new ERC20s
            weth = IERC20(address(new MockWETH("Wrapped ETH", "WETH", 18)));
            usdt = new MockERC20("USDT", "USDT", 6);
            usdc = new MockERC20("USDC", "USDC", 18);
            dai = new MockERC20("DAI", "DAI", 18);
            wbtc = new MockERC20("WBTC", "WBTC", 18);
            lon = new MockERC20("LON", "LON", 18);
            ankreth = new MockERC20("ANKRETH", "ANKRETH", 18);
        } else {
            // forked mainnet, load ERC20s using constant address
            weth = IERC20(WETH_ADDRESS);
            usdt = IERC20(USDT_ADDRESS);
            usdc = IERC20(USDC_ADDRESS);
            dai = IERC20(DAI_ADDRESS);
            wbtc = IERC20(WBTC_ADDRESS);
            lon = IERC20(LON_ADDRESS);
            ankreth = IERC20(ANKRETH_ADDRESS);
        }

        tokens = [weth, usdt, usdc, dai, wbtc, lon, ankreth];

        vm.label(address(weth), "WETH");
        vm.label(address(usdt), "USDT");
        vm.label(address(usdc), "USDC");
        vm.label(address(dai), "DAI");
        vm.label(address(wbtc), "WBTC");
        vm.label(address(lon), "LON");
        vm.label(address(ankreth), "ANKRETH");
    }

    function getChainId() internal returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }
}

function readAddresses(Vm vm) returns (string memory data) {
    uint256 chainId;
    assembly {
        chainId := chainid()
    }

    string memory fileName;
    if (chainId == 1) {
        fileName = "test/utils/config/mainnet.json";
    } else if (chainId == 5) {
        fileName = "test/utils/config/goerli.json";
    } else if (chainId == 42161) {
        fileName = "test/utils/config/arbitrumMainnet.json";
    } else if (chainId == 421613) {
        fileName = "test/utils/config/arbitrumGoerli.json";
    } else if (chainId == 31337) {
        fileName = "test/utils/config/local.json";
    } else {
        string memory errorMsg = string(abi.encodePacked("No address config support for network ", chainId));
        revert(errorMsg);
    }

    return vm.readFile(fileName);
}
