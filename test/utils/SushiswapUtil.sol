// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/interfaces/IUniswapRouterV2.sol";
import "test/utils/Addresses.sol";

function getSushiAmountsOut(
    address sushiswap,
    uint256 amountIn,
    address[] memory path
) view returns (uint256[] memory amounts) {
    return IUniswapRouterV2(sushiswap).getAmountsOut(amountIn, path);
}
