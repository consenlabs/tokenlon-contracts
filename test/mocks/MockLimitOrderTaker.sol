// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "contracts/abstracts/Ownable.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { IUniswapRouterV2 } from "contracts/interfaces/IUniswapRouterV2.sol";
import { MockERC1271Wallet } from "./MockERC1271Wallet.sol";

contract MockLimitOrderTaker is IStrategy, MockERC1271Wallet {
    using SafeERC20 for IERC20;

    IUniswapRouterV2 public immutable uniswapV2Router;

    constructor(address _operator, address _uniswapV2Router) MockERC1271Wallet(_operator) {
        uniswapV2Router = IUniswapRouterV2(_uniswapV2Router);
    }

    function executeStrategy(address inputToken, address outputToken, uint256 inputAmount, bytes calldata data) external payable override {
        (address routerAddr, bytes memory makerSpecificData) = abi.decode(data, (address, bytes));
        require(routerAddr == address(uniswapV2Router), "non supported protocol");

        (uint256 deadline, address[] memory path) = abi.decode(makerSpecificData, (uint256, address[]));
        _validateAMMPath(inputToken, outputToken, path);
        _tradeUniswapV2TokenToToken(inputAmount, deadline, path);
    }

    function _tradeUniswapV2TokenToToken(uint256 _inputAmount, uint256 _deadline, address[] memory _path) internal returns (uint256) {
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(_inputAmount, 0, _path, address(this), _deadline);
        return amounts[amounts.length - 1];
    }

    function _validateAMMPath(address _inputToken, address _outputToken, address[] memory _path) internal pure {
        require(_path.length >= 2, "path length must be at least two");
        require(_path[0] == _inputToken, "invalid path");
        require(_path[_path.length - 1] == _outputToken, "invalid path");
    }
}
