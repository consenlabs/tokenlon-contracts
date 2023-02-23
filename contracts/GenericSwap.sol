// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IGenericSwap } from "./interfaces/IGenericSwap.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { GeneralAsset } from "./libraries/GeneralAsset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract GenericSwap is IGenericSwap, TokenCollector, EIP712 {
    using SafeERC20 for IERC20;
    using GeneralAsset for address;

    bytes32 public constant GS_DATA_TYPEHASH = 0x9a6d9096b182513baa520ad9d0766c6e70d0637fcf40521146c04435396a0fdf;

    /*
        keccak256(
            abi.encodePacked(
                "GenericSwapData(",
                "address inputToken,",
                "address outputToken,",
                "uint256 inputAmount,",
                "uint256 minOutputAmount,",
                "address receiver,",
                "uint256 deadline,",
                "bytes inputData,",
                "bytes strategyData,",
                "uint256 salt",
                ")"
            )
        );
        */

    constructor(address _uniswapPermit2) TokenCollector(_uniswapPermit2) {}

    /// @param strategy The strategy contract
    /// @param swapData Swap data
    /// @return returnAmount Output amount of the swap
    function executeSwap(IStrategy strategy, GenericSwapData calldata swapData) external payable override returns (uint256 returnAmount) {
        return _executeSwap(strategy, swapData, msg.sender);
    }

    /// @param strategy The strategy contract
    /// @param swapData Swap data
    /// @return returnAmount Output amount of the swap
    function executeSwap(
        IStrategy strategy,
        GenericSwapData calldata swapData,
        address taker,
        uint256 salt,
        bytes calldata takerSig
    ) external payable override returns (uint256 returnAmount) {
        if (!SignatureValidator.isValidSignature(taker, getEIP712Hash(_getGSDataHash(swapData, salt)), takerSig)) revert();
        return _executeSwap(strategy, swapData, taker);
    }

    function _executeSwap(
        IStrategy strategy,
        GenericSwapData calldata swapData,
        address taker
    ) private returns (uint256 returnAmount) {
        address _inputToken = swapData.inputToken;
        address _outputToken = swapData.outputToken;

        if (_inputToken.isETH() && msg.value != swapData.inputAmount) {
            revert InvalidMsgValue();
        } else {
            _collect(_inputToken, taker, address(strategy), swapData.inputAmount, swapData.inputData);
        }

        strategy.executeStrategy(_inputToken, _outputToken, swapData.inputAmount, swapData.strategyData);

        returnAmount = _outputToken.generalBalanceOf(address(this));
        if (returnAmount < swapData.minOutputAmount) revert InsufficientOutput();

        _outputToken.generalTransfer(swapData.receiver, returnAmount);

        emit Swap(taker, _inputToken, _outputToken, swapData.inputAmount, returnAmount);
    }

    function _getGSDataHash(GenericSwapData memory _gsData, uint256 salt) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    GS_DATA_TYPEHASH,
                    _gsData.inputToken,
                    _gsData.outputToken,
                    _gsData.inputAmount,
                    _gsData.minOutputAmount,
                    _gsData.receiver,
                    _gsData.deadline,
                    _gsData.inputData,
                    _gsData.strategyData,
                    salt
                )
            );
    }
}
