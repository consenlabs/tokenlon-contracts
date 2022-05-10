// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "../interfaces/IUniswapRouterV2.sol";

library LibUniswapV2 {
    struct SwapExactTokensForTokensParams {
        address tokenIn;
        uint256 tokenInAmount;
        address tokenOut;
        uint256 tokenOutAmountMin;
        address[] path;
        address to;
        uint256 deadline;
    }

    function swapExactTokensForTokens(address _uniswapV2Router, SwapExactTokensForTokensParams memory _params) internal returns (uint256 amount) {
        _validatePath(_params.path, _params.tokenIn, _params.tokenOut);

        uint256[] memory amounts = IUniswapRouterV2(_uniswapV2Router).swapExactTokensForTokens(
            _params.tokenInAmount,
            _params.tokenOutAmountMin,
            _params.path,
            _params.to,
            _params.deadline
        );

        return amounts[amounts.length - 1];
    }

    function _validatePath(
        address[] memory _path,
        address _tokenIn,
        address _tokenOut
    ) internal {
        require(_path.length >= 2, "UniswapV2: Path length must be at least two");
        require(_path[0] == _tokenIn, "UniswapV2: First element of path must match token in");
        require(_path[_path.length - 1] == _tokenOut, "UniswapV2: Last element of path must match token out");
    }
}
