// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IGenericSwap } from "./interfaces/IGenericSwap.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { GeneralOrder } from "./interfaces/IGeneralOrder.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract GenericSwap is IGenericSwap, TokenCollector, EIP712 {
    using SafeERC20 for IERC20;
    using Asset for address;

    // FIXME to confirm with ethers.js
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

    mapping(bytes32 => bool) private filledSwap;

    constructor(address _uniswapPermit2) TokenCollector(_uniswapPermit2) {}

    /// @param swapData Swap data
    /// @return returnAmount Output amount of the swap
    function executeSwap(GenericSwapData calldata swapData) external payable override returns (uint256 returnAmount) {
        return _executeSwap(swapData, msg.sender);
    }

    /// @param swapData Swap data
    /// @param taker Claimed taker address
    /// @param takerSig Taker signature
    /// @return returnAmount Output amount of the swap
    function executeSwap(
        GenericSwapData calldata swapData,
        address taker,
        bytes calldata takerSig
    ) external payable override returns (uint256 returnAmount) {
        bytes32 swapHash = getEIP712Hash(_getGSDataHash(swapData));
        if (filledSwap[swapHash]) revert AlreadyFilled();
        if (!SignatureValidator.isValidSignature(taker, swapHash, takerSig)) revert InvalidSignature();
        filledSwap[swapHash] = true;
        return _executeSwap(swapData, taker);
    }

    function _executeSwap(GenericSwapData memory _swapData, address _authorizedUser) private returns (uint256 returnAmount) {
        GeneralOrder memory _order = _swapData.order;

        // check if _authorizedUser is allowed to fill the order
        if (_order.taker != _authorizedUser) revert InvalidTaker();

        address _inputToken = _order.inputToken;
        address _outputToken = _order.outputToken;

        if (_inputToken.isETH() && msg.value != _order.inputAmount) revert InvalidMsgValue();

        if (!_inputToken.isETH()) {
            _collect(_inputToken, _order.taker, _order.maker, _order.inputAmount, _order.inputTokenPermit);
        }

        IStrategy(_order.maker).executeStrategy{ value: msg.value }(_inputToken, _outputToken, _order.inputAmount, _swapData.strategyData);

        returnAmount = _outputToken.getBalance(address(this));
        if (returnAmount < _order.minOutputAmount) revert InsufficientOutput();

        _outputToken.transferTo(_order.recipient, returnAmount);

        emit Swap(_order.taker, _inputToken, _outputToken, _order.inputAmount, returnAmount);
    }

    function _getGSDataHash(GenericSwapData memory _gsData) private pure returns (bytes32) {
        // FIXME to confirm with ethers.js
        return keccak256(abi.encode(GS_DATA_TYPEHASH, _gsData.order, _gsData.strategyData));
    }
}
