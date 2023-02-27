// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "./abstracts/Ownable.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { IUniswapRouterV2 } from "./interfaces/IUniswapRouterV2.sol";

contract AMMStrategy is IStrategy, Ownable {
    using SafeERC20 for IERC20;

    address public genericSwap;
    IUniswapRouterV2 public immutable uniswapV2Router;
    IUniswapRouterV2 public immutable sushiwapRouter;

    constructor(
        address _owner,
        address _genericSwap,
        address _sushiwapRouter,
        address _uniswapV2Router
    ) Ownable(_owner) {
        genericSwap = _genericSwap;
        sushiwapRouter = IUniswapRouterV2(_sushiwapRouter);
        uniswapV2Router = IUniswapRouterV2(_uniswapV2Router);
    }

    modifier onlyGenericSwap() {
        require(msg.sender == genericSwap, "not from GenericSwap contract");
        _;
    }

    function approveTokenList(
        address[] calldata tokenList,
        address[] calldata spenderList,
        uint256 amount
    ) external onlyOwner {
        for (uint256 i = 0; i < tokenList.length; ++i) {
            for (uint256 j = 0; j < spenderList.length; ++j) {
                IERC20(tokenList[i]).safeApprove(spenderList[j], amount);
            }
        }
    }

    function executeStrategy(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        bytes calldata data
    ) external override onlyGenericSwap {
        (address[] memory routerAddrList, bytes[] memory makerSpecificDataList) = abi.decode(data, (address[], bytes[]));
        require(routerAddrList.length > 0 && routerAddrList.length == makerSpecificDataList.length, "wrong array lengths");
        uint256 outputAmount = 0;
        for (uint256 i = 0; i < routerAddrList.length; i++) {
            if (routerAddrList[i] == address(uniswapV2Router)) {
                outputAmount += _tradeUniswapV2TokenToToken(inputToken, outputToken, inputAmount, makerSpecificDataList[i]);
            } else if (routerAddrList[i] == address(sushiwapRouter)) {
                outputAmount += _tradeUniswapV2TokenToToken(inputToken, outputToken, inputAmount, makerSpecificDataList[i]);
            }
        }
        IERC20(outputToken).safeTransfer(genericSwap, outputAmount);
    }

    function _tradeUniswapV2TokenToToken(
        address _inputToken,
        address _outputToken,
        uint256 _inputAmount,
        bytes memory _makerSpecificData
    ) internal returns (uint256) {
        (uint256 deadline, address[] memory path) = abi.decode(_makerSpecificData, (uint256, address[]));
        _validateAMMPath(_inputToken, _outputToken, path);
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(_inputAmount, 0, path, address(this), deadline);
        return amounts[amounts.length - 1];
    }

    function _tradeSushiwapV2TokenToToken(
        address _inputToken,
        address _outputToken,
        uint256 _inputAmount,
        bytes memory _makerSpecificData
    ) internal returns (uint256) {
        (uint256 deadline, address[] memory path) = abi.decode(_makerSpecificData, (uint256, address[]));
        _validateAMMPath(_inputToken, _outputToken, path);
        uint256[] memory amounts = sushiwapRouter.swapExactTokensForTokens(_inputAmount, 0, path, address(this), deadline);
        return amounts[amounts.length - 1];
    }

    function _validateAMMPath(
        address _inputToken,
        address _outputToken,
        address[] memory _path
    ) internal pure {
        require(_path.length >= 2, "path length must be at least two");
        require(_path[0] == _inputToken, "invalid path");
        require(_path[_path.length - 1] == _outputToken, "invalid path");
    }
}
