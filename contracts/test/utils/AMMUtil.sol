// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "contracts/interfaces/IBalancerV2Vault.sol";
import "contracts-test/utils/UniswapV3Util.sol";

function _encodeUniswapSinglePoolData(uint256 swapType, uint24 poolFee) pure returns (bytes memory) {
    return abi.encode(swapType, poolFee);
}

function _encodeUniswapMultiPoolData(
    uint256 swapType,
    address[] memory path,
    uint24[] memory poolFees
) pure returns (bytes memory) {
    return abi.encode(swapType, encodePath(path, poolFees));
}

function _encodeBalancerData(IBalancerV2Vault.BatchSwapStep[] memory swapSteps) pure returns (bytes memory) {
    return abi.encode(swapSteps);
}

function _encodeCurveData(uint256 version) pure returns (bytes memory) {
    return abi.encode(version);
}
