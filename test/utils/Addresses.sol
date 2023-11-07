// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test, Vm } from "forge-std/Test.sol";

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

    address CURVE_TRICRYPTO2_POOL_ADDRESS = abi.decode(vm.parseJson(file, "$.CURVE_TRICRYPTO2_POOL_ADDRESS"), (address));
    address SUSHISWAP_ADDRESS = abi.decode(vm.parseJson(file, "$.SUSHISWAP_ADDRESS"), (address));
    address UNISWAP_V2_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V2_ADDRESS"), (address));
    address UNISWAP_V3_QUOTER_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_V3_QUOTER_ADDRESS"), (address));
    address UNISWAP_PERMIT2_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_PERMIT2_ADDRESS"), (address));
    address UNISWAP_UNIVERSAL_ROUTER_ADDRESS = abi.decode(vm.parseJson(file, "$.UNISWAP_UNIVERSAL_ROUTER_ADDRESS"), (address));

    function getChainId() internal view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }
}

function readAddresses(Vm vm) view returns (string memory data) {
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

function computeContractAddress(address deployer, uint8 nonce) pure returns (address) {
    // TODO support nonce larger than uint8 max
    bytes memory rlpEncoded = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(uint8(nonce)));
    return address(uint160(uint256(keccak256(rlpEncoded))));
}
