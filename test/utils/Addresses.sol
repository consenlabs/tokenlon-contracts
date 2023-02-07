// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";

address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

contract Addresses is Test {
    string private file = readAddresses(vm);

    address WETH_ADDRESS = abi.decode(vm.parseJson(file, "$.WETH_ADDRESS"), (address));
    address USDT_ADDRESS = abi.decode(vm.parseJson(file, "$.USDT_ADDRESS"), (address));
    address USDC_ADDRESS = abi.decode(vm.parseJson(file, "$.USDC_ADDRESS"), (address));
    address CRV_ADDRESS = abi.decode(vm.parseJson(file, "$.CRV_ADDRESS"), (address));
    address TUSD_ADDRESS = abi.decode(vm.parseJson(file, "$.TUSD_ADDRESS"), (address));
    address DAI_ADDRESS = abi.decode(vm.parseJson(file, "$.DAI_ADDRESS"), (address));
    address LON_ADDRESS = abi.decode(vm.parseJson(file, "$.LON_ADDRESS"), (address));
    address WBTC_ADDRESS = abi.decode(vm.parseJson(file, "$.WBTC_ADDRESS"), (address));
    address ANKRETH_ADDRESS = abi.decode(vm.parseJson(file, "$.ANKRETH_ADDRESS"), (address));

    address UNISWAP_V2_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V2_ADDRESS"), (address));
    address SUSHISWAP_ADDRESS = abi.decode(vm.parseJson(file, "$.SUSHISWAP_ADDRESS"), (address));
    address UNISWAP_V3_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V3_ADDRESS"), (address));
    address UNISWAP_V3_QUOTER_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V3_QUOTER_ADDRESS"), (address));
    address CURVE_USDT_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_USDT_POOL_ADDRESS"), (address));
    address CURVE_COMPOUND_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_COMPOUND_POOL_ADDRESS"), (address));
    address CURVE_Y_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_Y_POOL_ADDRESS"), (address));
    address CURVE_3_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_3_POOL_ADDRESS"), (address));
    address CURVE_TRICRYPTO2_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_TRICRYPTO2_POOL_ADDRESS"), (address));
    address CURVE_ANKRETH_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_ANKRETH_POOL_ADDRESS"), (address));
    address BALANCER_V2_ADDRESS = abi.decode(vm.parseJson(file, "$.BALANCER_V2_ADDRESS"), (address));

    // Curve coins
    address cDAI_ADDRESS = abi.decode(vm.parseJson(file, "$.cDAI_ADDRESS"), (address));
    address cUSDC_ADDRESS = abi.decode(vm.parseJson(file, "$.cUSDC_ADDRESS"), (address));
    address yDAI_ADDRESS = abi.decode(vm.parseJson(file, "$.yDAI_ADDRESS"), (address));
    address yUSDC_ADDRESS = abi.decode(vm.parseJson(file, "$.yUSDC_ADDRESS"), (address));
    address yUSDT_ADDRESS = abi.decode(vm.parseJson(file, "$.yUSDT_ADDRESS"), (address));
    address yTUSD_ADDRESS = abi.decode(vm.parseJson(file, "$.yTUSD_ADDRESS"), (address));

    address ARBITRUM_L1_GATEWAY_ROUTER_ADDR = abi.decode(vm.parseJson(file, "$.ARBITRUM_L1_GATEWAY_ROUTER_ADDR"), (address));
    address ARBITRUM_L1_BRIDGE_ADDR = abi.decode(vm.parseJson(file, "$.ARBITRUM_L1_BRIDGE_ADDR"), (address));
    address OPTIMISM_L1_STANDARD_BRIDGE_ADDR = abi.decode(vm.parseJson(file, "$.OPTIMISM_L1_STANDARD_BRIDGE_ADDR"), (address));

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
