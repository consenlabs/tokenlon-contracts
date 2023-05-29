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
    function fillLimitOrder(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        uint256 takerTokenAmount,
        uint256 makerTokenAmount,
        address recipient,
        bytes calldata extraAction,
        bytes calldata takerTokenPermit
    ) external payable override returns (uint256, uint256) {
        // validate the constrain of the order
        if (order.expiry <= block.timestamp) revert ExpiredOrder();
        if (order.taker != address(0) && msg.sender == order.taker) revert InvalidTaker();

        // validate the status of the order
        bytes32 orderHash = getLimitOrderHash(order);
        if (orderHashToCanceled[orderHash]) revert CanceledOrder();

        // validate maker signature
        if (!SignatureValidator.isValidSignature(order.maker, getEIP712Hash(orderHash), makerSignature)) revert InvalidSignature();

        // get the quote of this fill
        (uint256 takerTokenQuota, uint256 makerTokenQuota) = _quoteOrder(order, orderHash, makerTokenAmount);

        // check if taker provide enough amount for this fill (better price is allowed)
        if (takerTokenAmount < takerTokenQuota) revert InvalidTakingAmount();

        // maker -> taker
        _collect(order.makerToken, order.maker, address(this), makerTokenQuota, order.makerTokenPermit);
        uint256 fee = (makerTokenQuota * order.feeFactor) / Constant.BPS_MAX;
        order.makerToken.transferTo(payable(recipient), makerTokenQuota - fee);
        // collect fee if present
        order.makerToken.transferTo(feeCollector, fee);

        if (extraAction.length != 0) {
            (address strategy, bytes memory strategyData) = abi.decode(extraAction, (address, bytes));
            IStrategy(strategy).executeStrategy(order.makerToken, order.takerToken, makerTokenQuota, strategyData);
        }

        // taker -> maker
        if (order.takerToken.isETH()) {
            if (msg.value != takerTokenAmount) revert InvalidMsgValue();
            Asset.transferTo(Constant.ETH_ADDRESS, order.maker, takerTokenAmount);
        } else {
            _collect(order.takerToken, msg.sender, order.maker, takerTokenAmount, takerTokenPermit);
        }

        // avoid stack too deep error
        _emitLimitOrderFilled(order, orderHash, takerTokenAmount, makerTokenQuota - fee, fee, recipient);

        return (takerTokenAmount, makerTokenQuota - fee);
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

    function _quoteOrder(
        LimitOrder memory _order,
        bytes32 _orderHash,
        uint256 _makerTokenAmount
    ) internal returns (uint256, uint256) {
        uint256 makerTokenFilledAmount = orderHashToMakerTokenFilledAmount[_orderHash];

        if (makerTokenFilledAmount >= _order.makerTokenAmount) revert FilledOrder();

        uint256 makerTokenFillableAmount = _order.makerTokenAmount - makerTokenFilledAmount;
        // FIXME this assume if quota is smaller, then still proceed
        uint256 makerTokenQuota = Math.min(_makerTokenAmount, makerTokenFillableAmount);
        uint256 takerTokenQuota = ((makerTokenQuota * _order.takerTokenAmount) / _order.makerTokenAmount);

        require(makerTokenQuota != 0 && takerTokenQuota != 0, "LimitOrder: zero token amount");

        // record fill amount of this tx
        orderHashToMakerTokenFilledAmount[_orderHash] = makerTokenFilledAmount + makerTokenQuota;

        return (takerTokenQuota, makerTokenQuota);
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
