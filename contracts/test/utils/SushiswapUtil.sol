pragma solidity ^0.7.6;

import "./Addresses.sol";
import "../../interfaces/IUniswapRouterV2.sol";

abstract contract SushiswapUtil {
    IUniswapRouterV2 router = IUniswapRouterV2(Addresses.SUSHISWAP_ADDRESS);

    function getSushiAmountsOut(uint256 amountIn, address[] memory path) internal returns (uint256[] memory amounts) {
        return router.getAmountsOut(amountIn, path);
    }
}
