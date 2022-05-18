pragma solidity ^0.7.6;

import "./Addresses.sol";

interface IQuoter {
    function quoteExactInput(bytes memory path, uint256 amountIn) external returns (uint256 amountOut);

    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);

    function quoteExactOutput(bytes memory path, uint256 amountOut) external returns (uint256 amountIn);

    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);
}

abstract contract UniswapV3Util {
    IQuoter quoter = IQuoter(Addresses.UNISWAP_V3_QUOTER_ADDR);

    function quoteUniswapV3ExactInput(bytes memory path, uint256 amountIn) internal returns (uint256) {
        return quoter.quoteExactInput(path, amountIn);
    }
}
