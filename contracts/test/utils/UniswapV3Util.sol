pragma solidity ^0.7.6;

import "./Addresses.sol";

uint24 constant FEE_LOW = 500;
uint24 constant FEE_MEDIUM = 3000;
uint24 constant FEE_HIGH = 10000;

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

function encodePath(address[] memory path, uint24[] memory fees) returns (bytes memory) {
    bytes memory res;
    for (uint256 i = 0; i < fees.length; i++) {
        res = abi.encodePacked(res, path[i], fees[i]);
    }
    res = abi.encodePacked(res, path[path.length - 1]);
    return res;
}

function quoteUniswapV3ExactInput(bytes memory path, uint256 amountIn) returns (uint256) {
    return IQuoter(UNISWAP_V3_QUOTER_ADDRESS).quoteExactInput(path, amountIn);
}
