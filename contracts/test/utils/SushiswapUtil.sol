// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./Addresses.sol";
import "../../interfaces/IUniswapRouterV2.sol";

function getSushiAmountsOut(uint256 amountIn, address[] memory path) view returns (uint256[] memory amounts) {
    return IUniswapRouterV2(SUSHISWAP_ADDRESS).getAmountsOut(amountIn, path);
}
