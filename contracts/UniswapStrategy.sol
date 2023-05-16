// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "contracts/abstracts/Ownable.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { IUniswapRouterV2 } from "contracts/interfaces/IUniswapRouterV2.sol";

contract UniswapStrategy is IStrategy, Ownable {
    using SafeERC20 for IERC20;

    address public genericSwap;
    IUniswapRouterV2 public immutable uniswapV2Router;

    constructor(
        address _owner,
        address _genericSwap,
        address _uniswapV2Router
    ) Ownable(_owner) {
        genericSwap = _genericSwap;
        uniswapV2Router = IUniswapRouterV2(_uniswapV2Router);
    }

    modifier onlyGenericSwap() {
        require(msg.sender == genericSwap, "not from GenericSwap contract");
        _;
    }

    function approveToken(
        address token,
        address spender,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeApprove(spender, amount);
    }

    function executeStrategy(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        bytes calldata data
    ) external payable override onlyGenericSwap {
        (address routerAddr, bytes memory makerSpecificData) = abi.decode(data, (address, bytes));
        require(routerAddr == address(uniswapV2Router), "non supported protocol");

        (uint256 deadline, address[] memory path) = abi.decode(makerSpecificData, (uint256, address[]));
        _validateAMMPath(inputToken, outputToken, path);
        uint256 receivedAmount = _tradeUniswapV2TokenToToken(inputAmount, deadline, path);
        IERC20(outputToken).safeTransfer(genericSwap, receivedAmount);
    }

    function _tradeUniswapV2TokenToToken(
        uint256 _inputAmount,
        uint256 _deadline,
        address[] memory _path
    ) internal returns (uint256) {
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(_inputAmount, 0, _path, address(this), _deadline);
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
