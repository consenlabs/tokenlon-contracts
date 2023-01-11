// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";

address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

contract Addresses is Test {
    // All addresses defaults to mainnet addresses
    address WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDT_ADDRESS = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address CRV_ADDRESS = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address TUSD_ADDRESS = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address LON_ADDRESS = 0x0000000000095413afC295d19EDeb1Ad7B71c952;
    address WBTC_ADDRESS = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address ANKRETH_ADDRESS = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;

    address UNISWAP_V2_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address SUSHISWAP_ADDRESS = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address UNISWAP_V3_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address UNISWAP_V3_QUOTER_ADDRESS = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address CURVE_USDT_POOL_ADDRESS = 0x52EA46506B9CC5Ef470C5bf89f17Dc28bB35D85C;
    address CURVE_COMPOUND_POOL_ADDRESS = 0xA2B47E3D5c44877cca798226B7B8118F9BFb7A56;
    address CURVE_Y_POOL_ADDRESS = 0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51;
    address CURVE_3_POOL_ADDRESS = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address CURVE_TRICRYPTO2_POOL_ADDRESS = 0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5;
    address CURVE_ANKRETH_POOL_ADDRESS = 0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;
    address BALANCER_V2_ADDRESS = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // Curve coins
    address cDAI_ADDRESS = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address cUSDC_ADDRESS = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address yDAI_ADDRESS = 0x16de59092dAE5CcF4A1E6439D611fd0653f0Bd01;
    address yUSDC_ADDRESS = 0xd6aD7a6750A7593E092a9B218d66C0A814a3436e;
    address yUSDT_ADDRESS = 0x83f798e925BcD4017Eb265844FDDAbb448f1707D;
    address yTUSD_ADDRESS = 0x73a052500105205d34Daf004eAb301916DA8190f;

    address ARBITRUM_L1_GATEWAY_ROUTER_ADDR = 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef;
    address ARBITRUM_L1_BRIDGE_ADDR = 0x8315177aB297bA92A06054cE80a67Ed4DBd7ed3a;
    address OPTIMISM_L1_STANDARD_BRIDGE_ADDR = 0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1;

    constructor() {
        uint256 chainId = getChainId();
        string memory fileName;

        if (chainId == 1) {
            // Defaults are mainnet addresses
            return;
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

        cDAI_ADDRESS = abi.decode(vm.parseJson(file, "cDAI_ADDRESS"), (address));
        cUSDC_ADDRESS = abi.decode(vm.parseJson(file, "cUSDC_ADDRESS"), (address));
        yDAI_ADDRESS = abi.decode(vm.parseJson(file, "yDAI_ADDRESS"), (address));
        yUSDC_ADDRESS = abi.decode(vm.parseJson(file, "yUSDC_ADDRESS"), (address));
        yUSDT_ADDRESS = abi.decode(vm.parseJson(file, "yUSDT_ADDRESS"), (address));
        yTUSD_ADDRESS = abi.decode(vm.parseJson(file, "yTUSD_ADDRESS"), (address));

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
