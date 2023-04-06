// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IGenericSwap } from "./interfaces/IGenericSwap.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { Offer } from "./libraries/Offer.sol";
import { GenericSwapData, getGSDataHash } from "./libraries/GenericSwapData.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract GenericSwap is IGenericSwap, TokenCollector, EIP712 {
    using SafeERC20 for IERC20;
    using Asset for address;

    mapping(bytes32 => bool) private filledSwap;

    constructor(address _uniswapPermit2) TokenCollector(_uniswapPermit2) {}

    /// @param swapData Swap data
    /// @return returnAmount Output amount of the swap
    function executeSwap(GenericSwapData calldata swapData, bytes calldata takerTokenPermit) external payable override returns (uint256 returnAmount) {
        return _executeSwap(swapData, msg.sender, takerTokenPermit);
    }

    /// @param swapData Swap data
    /// @param taker Claimed taker address
    /// @param takerSig Taker signature
    /// @return returnAmount Output amount of the swap
    function executeSwap(
        GenericSwapData calldata swapData,
        bytes calldata takerTokenPermit,
        address taker,
        bytes calldata takerSig
    ) external payable override returns (uint256 returnAmount) {
        bytes32 swapHash = getEIP712Hash(getGSDataHash(swapData));
        if (filledSwap[swapHash]) revert AlreadyFilled();
        if (!SignatureValidator.isValidSignature(taker, swapHash, takerSig)) revert InvalidSignature();
        filledSwap[swapHash] = true;
        return _executeSwap(swapData, taker, takerTokenPermit);
    }

    function _executeSwap(
        GenericSwapData memory _swapData,
        address _authorizedUser,
        bytes memory _takerTokenPermit
    ) private returns (uint256 returnAmount) {
        Offer memory _offer = _swapData.offer;

        // check if _authorizedUser is allowed to fill the offer
        if (_offer.taker != _authorizedUser) revert InvalidTaker();

        address _inputToken = _offer.takerToken;
        address _outputToken = _offer.makerToken;

        if (_inputToken.isETH() && msg.value != _offer.takerTokenAmount) revert InvalidMsgValue();

        if (!_inputToken.isETH()) {
            _collect(_inputToken, _offer.taker, _offer.maker, _offer.takerTokenAmount, _takerTokenPermit);
        }

        IStrategy(_offer.maker).executeStrategy{ value: msg.value }(_inputToken, _outputToken, _offer.takerTokenAmount, _swapData.strategyData);

        returnAmount = _outputToken.getBalance(address(this));
        if (returnAmount < _offer.minMakerTokenAmount) revert InsufficientOutput();

        _outputToken.transferTo(_swapData.recipient, returnAmount);

        emit Swap(_offer.maker, _offer.taker, _swapData.recipient, _inputToken, _offer.takerTokenAmount, _outputToken, returnAmount);
    }
}
