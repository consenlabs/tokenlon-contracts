// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import { ISwapRouter } from "../interfaces/IUniswapV3SwapRouter.sol";
import { Path } from "./UniswapV3PathLib.sol";

library LibUniswapV3 {
    using Path for bytes;

    enum SwapType {
        None,
        ExactInputSingle,
        ExactInput
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(address _uniswapV3Router, ExactInputSingleParams memory _params) internal returns (uint256 amount) {
        return
            ISwapRouter(_uniswapV3Router).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: _params.tokenIn,
                    tokenOut: _params.tokenOut,
                    fee: _params.fee,
                    recipient: _params.recipient,
                    deadline: _params.deadline,
                    amountIn: _params.amountIn,
                    amountOutMinimum: _params.amountOutMinimum,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    struct ExactInputParams {
        address tokenIn;
        address tokenOut;
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(address _uniswapV3Router, ExactInputParams memory _params) internal returns (uint256 amount) {
        _validatePath(_params.path, _params.tokenIn, _params.tokenOut);
        return
            ISwapRouter(_uniswapV3Router).exactInput(
                ISwapRouter.ExactInputParams({
                    path: _params.path,
                    recipient: _params.recipient,
                    deadline: _params.deadline,
                    amountIn: _params.amountIn,
                    amountOutMinimum: _params.amountOutMinimum
                })
            );
    }

    function _validatePath(
        bytes memory _path,
        address _tokenIn,
        address _tokenOut
    ) internal pure {
        (address tokenA, address tokenB, ) = _path.decodeFirstPool();

        if (_path.hasMultiplePools()) {
            _path = _path.skipToken();
            while (_path.hasMultiplePools()) {
                _path = _path.skipToken();
            }
            (, tokenB, ) = _path.decodeFirstPool();
        }

        require(tokenA == _tokenIn, "UniswapV3: first element of path must match token in");
        require(tokenB == _tokenOut, "UniswapV3: last element of path must match token out");
    }
}
