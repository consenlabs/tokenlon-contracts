// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";

address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

contract Addresses is Test {
    address WETH_ADDRESS;
    address USDT_ADDRESS;
    address USDC_ADDRESS;
    address CRV_ADDRESS;
    address TUSD_ADDRESS;
    address DAI_ADDRESS;
    address LON_ADDRESS;
    address WBTC_ADDRESS;
    address ANKRETH_ADDRESS;

    address UNISWAP_V2_ADDRESS;
    address SUSHISWAP_ADDRESS;
    address UNISWAP_V3_ADDRESS;
    address UNISWAP_V3_QUOTER_ADDRESS;
    address CURVE_USDT_POOL_ADDRESS;
    address CURVE_COMPOUND_POOL_ADDRESS;
    address CURVE_Y_POOL_ADDRESS;
    address CURVE_3_POOL_ADDRESS;
    address CURVE_TRICRYPTO2_POOL_ADDRESS;
    address CURVE_ANKRETH_POOL_ADDRESS;
    address BALANCER_V2_ADDRESS;

    // Curve coins
    address cDAI_ADDRESS;
    address cUSDC_ADDRESS;
    address yDAI_ADDRESS;
    address yUSDC_ADDRESS;
    address yUSDT_ADDRESS;
    address yTUSD_ADDRESS;

    address ARBITRUM_L1_GATEWAY_ROUTER_ADDR;
    address ARBITRUM_L1_BRIDGE_ADDR;
    address OPTIMISM_L1_STANDARD_BRIDGE_ADDR;

    constructor() {
        uint256 chainId = getChainId();
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
            // Local testnet
            return;
        } else {
            string memory errorMsg = string(abi.encodePacked("No address config support for network ", chainId));
            revert(errorMsg);
        }
        string memory file = vm.readFile(fileName);

        WETH_ADDRESS = abi.decode(vm.parseJson(file, "WETH_ADDRESS"), (address));
        USDT_ADDRESS = abi.decode(vm.parseJson(file, "USDT_ADDRESS"), (address));
        USDC_ADDRESS = abi.decode(vm.parseJson(file, "USDC_ADDRESS"), (address));
        CRV_ADDRESS = abi.decode(vm.parseJson(file, "CRV_ADDRESS"), (address));
        TUSD_ADDRESS = abi.decode(vm.parseJson(file, "TUSD_ADDRESS"), (address));
        DAI_ADDRESS = abi.decode(vm.parseJson(file, "DAI_ADDRESS"), (address));
        LON_ADDRESS = abi.decode(vm.parseJson(file, "LON_ADDRESS"), (address));
        WBTC_ADDRESS = abi.decode(vm.parseJson(file, "WBTC_ADDRESS"), (address));
        ANKRETH_ADDRESS = abi.decode(vm.parseJson(file, "ANKRETH_ADDRESS"), (address));

        UNISWAP_V2_ADDRESS = abi.decode(vm.parseJson(file, "UNISWAP_V2_ADDRESS"), (address));
        SUSHISWAP_ADDRESS = abi.decode(vm.parseJson(file, "SUSHISWAP_ADDRESS"), (address));
        UNISWAP_V3_ADDRESS = abi.decode(vm.parseJson(file, "UNISWAP_V3_ADDRESS"), (address));
        UNISWAP_V3_QUOTER_ADDRESS = abi.decode(vm.parseJson(file, "UNISWAP_V3_QUOTER_ADDRESS"), (address));
        CURVE_USDT_POOL_ADDRESS = abi.decode(vm.parseJson(file, "CURVE_USDT_POOL_ADDRESS"), (address));
        CURVE_COMPOUND_POOL_ADDRESS = abi.decode(vm.parseJson(file, "CURVE_COMPOUND_POOL_ADDRESS"), (address));
        CURVE_Y_POOL_ADDRESS = abi.decode(vm.parseJson(file, "CURVE_Y_POOL_ADDRESS"), (address));
        CURVE_3_POOL_ADDRESS = abi.decode(vm.parseJson(file, "CURVE_3_POOL_ADDRESS"), (address));
        CURVE_TRICRYPTO2_POOL_ADDRESS = abi.decode(vm.parseJson(file, "CURVE_TRICRYPTO2_POOL_ADDRESS"), (address));
        CURVE_ANKRETH_POOL_ADDRESS = abi.decode(vm.parseJson(file, "CURVE_ANKRETH_POOL_ADDRESS"), (address));
        BALANCER_V2_ADDRESS = abi.decode(vm.parseJson(file, "BALANCER_V2_ADDRESS"), (address));

        console2.logAddress(CURVE_COMPOUND_POOL_ADDRESS);
        cDAI_ADDRESS = abi.decode(vm.parseJson(file, "cDAI_ADDRESS"), (address));
        cUSDC_ADDRESS = abi.decode(vm.parseJson(file, "cUSDC_ADDRESS"), (address));
        yDAI_ADDRESS = abi.decode(vm.parseJson(file, "yDAI_ADDRESS"), (address));
        yUSDC_ADDRESS = abi.decode(vm.parseJson(file, "yUSDC_ADDRESS"), (address));
        yUSDT_ADDRESS = abi.decode(vm.parseJson(file, "yUSDT_ADDRESS"), (address));
        yTUSD_ADDRESS = abi.decode(vm.parseJson(file, "yTUSD_ADDRESS"), (address));
        console2.logAddress(yUSDT_ADDRESS);

        ARBITRUM_L1_GATEWAY_ROUTER_ADDR = abi.decode(vm.parseJson(file, "ARBITRUM_L1_GATEWAY_ROUTER_ADDR"), (address));
        ARBITRUM_L1_BRIDGE_ADDR = abi.decode(vm.parseJson(file, "ARBITRUM_L1_BRIDGE_ADDR"), (address));
        OPTIMISM_L1_STANDARD_BRIDGE_ADDR = abi.decode(vm.parseJson(file, "OPTIMISM_L1_STANDARD_BRIDGE_ADDR"), (address));
    }

    function getChainId() internal returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }
}
