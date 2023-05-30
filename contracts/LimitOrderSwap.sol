// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { ILimitOrderSwap } from "./interfaces/ILimitOrderSwap.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { Constant } from "./libraries/Constant.sol";
import { LimitOrder, getLimitOrderHash } from "./libraries/LimitOrder.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

/// @title LimitOrderSwap Contract
/// @author imToken Labs
contract LimitOrderSwap is ILimitOrderSwap, Ownable, TokenCollector, EIP712 {
    using Asset for address;

    IWETH public immutable weth;
    address payable public feeCollector;

    // how much maker token has been filled in an order
    mapping(bytes32 => uint256) public orderHashToMakerTokenFilledAmount;
    // whether an order is canceled or not
    mapping(bytes32 => bool) public orderHashToCanceled;

    constructor(
        address _owner,
        address _uniswapPermit2,
        address _allowanceTarget,
        IWETH _weth,
        address payable _feeCollector
    ) Ownable(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {
        weth = _weth;
        feeCollector = _feeCollector;
    }

    receive() external payable {}

    /// @notice Only owner can call
    /// @param _newFeeCollector The new address of fee collector
    function setFeeCollector(address payable _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert ZeroAddress();
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /// @inheritdoc ILimitOrderSwap
    function fillLimitOrderFullOrKill(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        TakerParams calldata takerParams
    ) external payable override {
        _fillLimitOrder(order, makerSignature, takerParams, true);
    }

    /// @inheritdoc ILimitOrderSwap
    function fillLimitOrder(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        TakerParams calldata takerParams
    ) external payable override {
        _fillLimitOrder(order, makerSignature, takerParams, false);
    }

    /// @inheritdoc ILimitOrderSwap
    function cancelOder(LimitOrder calldata order) external override {
        if (order.expiry <= uint64(block.timestamp)) revert ExpiredOrder();
        if (msg.sender != order.maker) revert NotOrderMaker();
        bytes32 orderHash = getLimitOrderHash(order);
        if (orderHashToCanceled[orderHash]) revert CanceledOrder();

        // Set canceled state to storage
        orderHashToCanceled[orderHash] = true;
        emit OrderCanceled(orderHash, order.maker);
    }

    function _fillLimitOrder(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        TakerParams calldata takerParams,
        bool fullOrKill
    ) private {
        (bytes32 orderHash, uint256 takerTokenQuota, uint256 makerTokenQuota) = _validateOrderAndQuote(
            order,
            makerSignature,
            takerParams.makerTokenAmount,
            fullOrKill
        );

        // check if taker provide enough amount for this fill (better price is allowed)
        if (takerParams.takerTokenAmount < takerTokenQuota) revert InvalidTakingAmount();

        // maker -> taker
        _collect(order.makerToken, order.maker, address(this), makerTokenQuota, order.makerTokenPermit);
        uint256 fee = (makerTokenQuota * order.feeFactor) / Constant.BPS_MAX;
        order.makerToken.transferTo(payable(takerParams.recipient), makerTokenQuota - fee);
        // collect fee if present
        order.makerToken.transferTo(feeCollector, fee);

        if (takerParams.extraAction.length != 0) {
            (address strategy, bytes memory strategyData) = abi.decode(takerParams.extraAction, (address, bytes));
            IStrategy(strategy).executeStrategy(order.makerToken, order.takerToken, makerTokenQuota, strategyData);
        }

        // taker -> maker
        if (order.takerToken.isETH()) {
            if (msg.value != takerParams.takerTokenAmount) revert InvalidMsgValue();
            Asset.transferTo(Constant.ETH_ADDRESS, order.maker, takerParams.takerTokenAmount);
        } else {
            _collect(order.takerToken, msg.sender, order.maker, takerParams.takerTokenAmount, takerParams.takerTokenPermit);
        }

        // avoid stack too deep error
        _emitLimitOrderFilled(order, orderHash, takerParams.takerTokenAmount, makerTokenQuota - fee, fee, takerParams.recipient);
    }

    function _validateOrderAndQuote(
        LimitOrder calldata _order,
        bytes calldata _makerSignature,
        uint256 _makerTokenAmount,
        bool _fullOrKill
    )
        internal
        returns (
            bytes32,
            uint256,
            uint256
        )
    {
        // validate the constrain of the order
        if (_order.expiry <= block.timestamp) revert ExpiredOrder();
        if (_order.taker != address(0) && msg.sender == _order.taker) revert InvalidTaker();

        // validate the status of the order
        bytes32 orderHash = getLimitOrderHash(_order);
        if (orderHashToCanceled[orderHash]) revert CanceledOrder();

        // validate maker signature
        if (!SignatureValidator.isValidSignature(_order.maker, getEIP712Hash(orderHash), _makerSignature)) revert InvalidSignature();

        // check whether the order is fully filled or not
        uint256 orderFilledAmount = orderHashToMakerTokenFilledAmount[orderHash];
        if (orderFilledAmount >= _order.makerTokenAmount) revert FilledOrder();

        // get the quote of the fill
        uint256 orderFillableAmount = _order.makerTokenAmount - orderFilledAmount;
        if (_fullOrKill && _makerTokenAmount > orderFillableAmount) revert NotEnoughForFill();
        uint256 makerTokenQuota = Math.min(_makerTokenAmount, orderFillableAmount);
        uint256 takerTokenQuota = ((makerTokenQuota * _order.takerTokenAmount) / _order.makerTokenAmount);
        if (makerTokenQuota == 0 && takerTokenQuota == 0) revert ZeroTokenAmount();

        // record fill amount of this tx
        orderHashToMakerTokenFilledAmount[orderHash] = orderFilledAmount + makerTokenQuota;

        return (orderHash, takerTokenQuota, makerTokenQuota);
    }

    function _emitLimitOrderFilled(
        LimitOrder memory _order,
        bytes32 _orderHash,
        uint256 _takerTokenSettleAmount,
        uint256 _makerTokenSettleAmount,
        uint256 _fee,
        address _recipient
    ) internal {
        emit LimitOrderFilled(
            _orderHash,
            msg.sender,
            _order.maker,
            _order.takerToken,
            _takerTokenSettleAmount,
            _order.makerToken,
            _makerTokenSettleAmount,
            _fee,
            _recipient
        );
    }
}
