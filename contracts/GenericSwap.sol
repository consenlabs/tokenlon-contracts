// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IGenericSwap } from "./interfaces/IGenericSwap.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { GenericSwapData, getGSDataHash } from "./libraries/GenericSwapData.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract GenericSwap is IGenericSwap, TokenCollector, EIP712 {
    using Asset for address;

    mapping(bytes32 => bool) private filledSwap;

    constructor(address _uniswapPermit2, address _allowanceTarget) TokenCollector(_uniswapPermit2, _allowanceTarget) {}

    receive() external payable {}

    /// @param swapData Swap data
    /// @return returnAmount Output amount of the swap
    function executeSwap(GenericSwapData calldata swapData, bytes calldata takerTokenPermit) external payable override returns (uint256 returnAmount) {
        returnAmount = _executeSwap(swapData, msg.sender, takerTokenPermit);

        _emitGSExecuted(getGSDataHash(swapData), swapData, msg.sender, returnAmount);
    }

    /// @param swapData Swap data
    /// @param taker Claimed taker address
    /// @param takerSig Taker signature
    /// @return returnAmount Output amount of the swap
    function executeSwapWithSig(
        GenericSwapData calldata swapData,
        bytes calldata takerTokenPermit,
        address taker,
        bytes calldata takerSig
    ) external payable override returns (uint256 returnAmount) {
        bytes32 swapHash = getGSDataHash(swapData);
        bytes32 gs712Hash = getEIP712Hash(swapHash);
        if (filledSwap[swapHash]) revert AlreadyFilled();
        filledSwap[swapHash] = true;
        if (!SignatureValidator.validateSignature(taker, gs712Hash, takerSig)) revert InvalidSignature();

        returnAmount = _executeSwap(swapData, taker, takerTokenPermit);

        _emitGSExecuted(swapHash, swapData, taker, returnAmount);
    }

    function _executeSwap(
        GenericSwapData calldata _swapData,
        address _authorizedUser,
        bytes calldata _takerTokenPermit
    ) private returns (uint256 returnAmount) {
        if (_swapData.expiry < block.timestamp) revert ExpiredOrder();
        if (_swapData.recipient == address(0)) revert ZeroAddress();

        address _inputToken = _swapData.takerToken;
        address _outputToken = _swapData.makerToken;

        if (_inputToken.isETH()) {
            if (msg.value != _swapData.takerTokenAmount) revert InvalidMsgValue();
        } else {
            if (msg.value != 0) revert InvalidMsgValue();
            _collect(_inputToken, _authorizedUser, _swapData.maker, _swapData.takerTokenAmount, _takerTokenPermit);
        }

        IStrategy(_swapData.maker).executeStrategy{ value: msg.value }(_inputToken, _outputToken, _swapData.takerTokenAmount, _swapData.strategyData);

        returnAmount = _outputToken.getBalance(address(this));
        if (returnAmount > 1) {
            unchecked {
                --returnAmount;
            }
        }
        if (returnAmount < _swapData.minMakerTokenAmount) revert InsufficientOutput();

        _outputToken.transferTo(_swapData.recipient, returnAmount);
    }

    function _emitGSExecuted(bytes32 _gsOfferHash, GenericSwapData calldata _swapData, address _taker, uint256 returnAmount) internal {
        emit Swap(
            _gsOfferHash,
            _swapData.maker,
            _taker,
            _swapData.recipient,
            _swapData.takerToken,
            _swapData.takerTokenAmount,
            _swapData.makerToken,
            returnAmount,
            _swapData.salt
        );
    }
}
