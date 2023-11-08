// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "contracts/abstracts/Ownable.sol";
import { IStrategy } from "contracts/interfaces/IStrategy.sol";
import { IUniswapSwapRouter02 } from "contracts/interfaces/IUniswapSwapRouter02.sol";
import { MockERC1271Wallet } from "./MockERC1271Wallet.sol";

contract MockLimitOrderTaker is IStrategy, MockERC1271Wallet {
    using SafeERC20 for IERC20;

    IUniswapSwapRouter02 public immutable uniswapRouter02;

    constructor(address _operator, address _uniswapRouter02) MockERC1271Wallet(_operator) {
        uniswapRouter02 = IUniswapSwapRouter02(_uniswapRouter02);
    }

    function executeStrategy(address inputToken, address outputToken, uint256 inputAmount, bytes calldata data) external payable override {
        (address routerAddr, bytes memory makerSpecificData) = abi.decode(data, (address, bytes));
        require(routerAddr == address(uniswapRouter02), "non supported protocol");

        address[] memory path = abi.decode(makerSpecificData, (address[]));
        _validateAMMPath(inputToken, outputToken, path);
        _tradeUniswapV2TokenToToken(inputAmount, path);
    }

    function _tradeUniswapV2TokenToToken(uint256 _inputAmount, address[] memory _path) internal returns (uint256) {
        return uniswapRouter02.swapExactTokensForTokens(_inputAmount, 0, _path, address(this));
    }

    function _validateAMMPath(address _inputToken, address _outputToken, address[] memory _path) internal pure {
        require(_path.length >= 2, "path length must be at least two");
        require(_path[0] == _inputToken, "invalid path");
        require(_path[_path.length - 1] == _outputToken, "invalid path");
    }
}
