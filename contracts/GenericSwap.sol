// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IGenericSwap } from "./interfaces/IGenericSwap.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { GenericSwapData, getGSDataHash } from "./libraries/GenericSwapData.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

/// @title GenericSwap Contract
/// @author imToken Labs
/// @notice This contract facilitates token swaps using SmartOrderStrategy strategies.
contract GenericSwap is IGenericSwap, TokenCollector, EIP712 {
    using Asset for address;

    /// @notice Mapping to keep track of filled swaps.
    /// @dev Stores the status of swaps to ensure they are not filled more than once.
    mapping(bytes32 swapHash => bool isFilled) public filledSwap;

    /// @notice Constructor to initialize the contract with the permit2 and allowance target.
    /// @param _uniswapPermit2 The address for Uniswap permit2.
    /// @param _allowanceTarget The address for the allowance target.
    constructor(address _uniswapPermit2, address _allowanceTarget) TokenCollector(_uniswapPermit2, _allowanceTarget) {}

    /// @notice Receive function to receive ETH.
    receive() external payable {}

    /// @inheritdoc IGenericSwap
    function executeSwap(GenericSwapData calldata swapData, bytes calldata takerTokenPermit) external payable returns (uint256 returnAmount) {
        returnAmount = _executeSwap(swapData, msg.sender, takerTokenPermit);

        _emitGSExecuted(getGSDataHash(swapData), swapData, msg.sender, returnAmount);
    }

    /// @inheritdoc IGenericSwap
    function executeSwapWithSig(
        GenericSwapData calldata swapData,
        bytes calldata takerTokenPermit,
        address taker,
        bytes calldata takerSig
    ) external payable returns (uint256 returnAmount) {
        bytes32 swapHash = getGSDataHash(swapData);
        bytes32 gs712Hash = getEIP712Hash(swapHash);
        if (filledSwap[swapHash]) revert AlreadyFilled();
        filledSwap[swapHash] = true;
        if (!SignatureValidator.validateSignature(taker, gs712Hash, takerSig)) revert InvalidSignature();

        returnAmount = _executeSwap(swapData, taker, takerTokenPermit);

        _emitGSExecuted(swapHash, swapData, taker, returnAmount);
    }

    /// @notice Executes a generic swap.
    /// @param _swapData The swap data containing details of the swap.
    /// @param _authorizedUser The address authorized to execute the swap.
    /// @param _takerTokenPermit The permit for the taker token.
    /// @return returnAmount The output amount of the swap.
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

    /// @notice Emits the Swap event after executing a generic swap.
    /// @param _gsOfferHash The hash of the generic swap offer.
    /// @param _swapData The swap data containing details of the swap.
    /// @param _taker The address of the taker.
    /// @param returnAmount The output amount of the swap.
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
