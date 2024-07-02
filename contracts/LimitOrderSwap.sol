// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
contract LimitOrderSwap is ILimitOrderSwap, Ownable, TokenCollector, EIP712, ReentrancyGuard {
    using Asset for address;

    uint256 private constant ORDER_CANCEL_AMOUNT_MASK = 1 << 255;

    IWETH public immutable weth;
    address payable public feeCollector;

    // how much maker token has been filled in an order
    mapping(bytes32 => uint256) public orderHashToMakerTokenFilledAmount;

    constructor(
        address _owner,
        address _uniswapPermit2,
        address _allowanceTarget,
        IWETH _weth,
        address payable _feeCollector
    ) Ownable(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {
        weth = _weth;
        if (_feeCollector == address(0)) revert ZeroAddress();
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
    function fillLimitOrder(LimitOrder calldata order, bytes calldata makerSignature, TakerParams calldata takerParams) external payable nonReentrant {
        _fillLimitOrder(order, makerSignature, takerParams, false);
    }

    /// @inheritdoc ILimitOrderSwap
    function fillLimitOrderFullOrKill(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        TakerParams calldata takerParams
    ) external payable nonReentrant {
        _fillLimitOrder(order, makerSignature, takerParams, true);
    }

    /// @inheritdoc ILimitOrderSwap
    function fillLimitOrderGroup(
        LimitOrder[] calldata orders,
        bytes[] calldata makerSignatures,
        uint256[] calldata makerTokenAmounts,
        address[] calldata profitTokens
    ) external payable nonReentrant {
        if (orders.length != makerSignatures.length || orders.length != makerTokenAmounts.length) revert InvalidParams();

        // validate orders and calculate takingAmounts
        uint256[] memory takerTokenAmounts = new uint256[](orders.length);
        uint256 wethToPay;
        address payable _feeCollector = feeCollector;
        for (uint256 i = 0; i < orders.length; ++i) {
            LimitOrder calldata order = orders[i];
            uint256 makingAmount = makerTokenAmounts[i];

            (bytes32 orderHash, uint256 orderFilledAmount) = _validateOrder(order, makerSignatures[i]);
            {
                uint256 orderAvailableAmount = order.makerTokenAmount - orderFilledAmount;
                if (makingAmount > orderAvailableAmount) revert NotEnoughForFill();
                takerTokenAmounts[i] = ((makingAmount * order.takerTokenAmount) / order.makerTokenAmount);

                if (makingAmount == 0) {
                    if (takerTokenAmounts[i] == 0) revert ZeroTokenAmount();
                }

                if (order.takerToken == address(weth)) {
                    wethToPay += takerTokenAmounts[i];
                }

                // record fill amount
                orderHashToMakerTokenFilledAmount[orderHash] = orderFilledAmount + makingAmount;
            }

            // collect maker tokens
            _collect(order.makerToken, order.maker, address(this), makingAmount, order.makerTokenPermit);

            // transfer fee if present
            uint256 fee = (makingAmount * order.feeFactor) / Constant.BPS_MAX;
            order.makerToken.transferTo(_feeCollector, fee);

            _emitLimitOrderFilled(order, orderHash, takerTokenAmounts[i], makingAmount - fee, fee, address(this));
        }

        // unwrap extra WETH in order to pay for ETH taker token and profit
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > wethToPay) {
            unchecked {
                weth.withdraw(wethBalance - wethToPay);
            }
        }

        for (uint256 i = 0; i < orders.length; ++i) {
            LimitOrder calldata order = orders[i];
            order.takerToken.transferTo(order.maker, takerTokenAmounts[i]);
        }

        // any token left is considered as profit
        for (uint256 i = 0; i < profitTokens.length; ++i) {
            uint256 profit = profitTokens[i].getBalance(address(this));
            profitTokens[i].transferTo(payable(msg.sender), profit);
        }
    }

    /// @inheritdoc ILimitOrderSwap
    function cancelOrder(LimitOrder calldata order) external nonReentrant {
        if (order.expiry < uint64(block.timestamp)) revert ExpiredOrder();
        if (msg.sender != order.maker) revert NotOrderMaker();
        bytes32 orderHash = getLimitOrderHash(order);
        uint256 orderFilledAmount = orderHashToMakerTokenFilledAmount[orderHash];
        if ((orderFilledAmount & ORDER_CANCEL_AMOUNT_MASK) != 0) revert CanceledOrder();
        if (orderFilledAmount >= order.makerTokenAmount) revert FilledOrder();

        // Set canceled state to storage
        orderHashToMakerTokenFilledAmount[orderHash] = orderFilledAmount | ORDER_CANCEL_AMOUNT_MASK;
        emit OrderCanceled(orderHash, order.maker);
    }

    function isOrderCanceled(bytes32 orderHash) external view returns (bool) {
        uint256 orderFilledAmount = orderHashToMakerTokenFilledAmount[orderHash];
        return (orderFilledAmount & ORDER_CANCEL_AMOUNT_MASK) != 0;
    }

    function _fillLimitOrder(LimitOrder calldata order, bytes calldata makerSignature, TakerParams calldata takerParams, bool fullOrKill) private {
        (bytes32 orderHash, uint256 takerSpendingAmount, uint256 makerSpendingAmount) = _validateOrderAndQuote(
            order,
            makerSignature,
            takerParams.takerTokenAmount,
            takerParams.makerTokenAmount,
            fullOrKill
        );

        // maker -> taker
        _collect(order.makerToken, order.maker, address(this), makerSpendingAmount, order.makerTokenPermit);
        uint256 fee = (makerSpendingAmount * order.feeFactor) / Constant.BPS_MAX;
        if (takerParams.recipient == address(0)) revert ZeroAddress();
        order.makerToken.transferTo(payable(takerParams.recipient), makerSpendingAmount - fee);
        // collect fee if present
        order.makerToken.transferTo(feeCollector, fee);

        if (takerParams.extraAction.length != 0) {
            (address strategy, bytes memory strategyData) = abi.decode(takerParams.extraAction, (address, bytes));
            IStrategy(strategy).executeStrategy(order.makerToken, order.takerToken, makerSpendingAmount - fee, strategyData);
        }

        // taker -> maker
        if (order.takerToken.isETH()) {
            if (msg.value != takerParams.takerTokenAmount) revert InvalidMsgValue();
            Asset.transferTo(Constant.ETH_ADDRESS, order.maker, takerSpendingAmount);
            uint256 ethRefund = takerParams.takerTokenAmount - takerSpendingAmount;
            Asset.transferTo(Constant.ETH_ADDRESS, payable(msg.sender), ethRefund);
        } else {
            if (msg.value != 0) revert InvalidMsgValue();
            _collect(order.takerToken, msg.sender, order.maker, takerSpendingAmount, takerParams.takerTokenPermit);
        }

        // avoid stack too deep error
        _emitLimitOrderFilled(order, orderHash, takerSpendingAmount, makerSpendingAmount - fee, fee, takerParams.recipient);
    }

    function _validateOrderAndQuote(
        LimitOrder calldata _order,
        bytes calldata _makerSignature,
        uint256 _takerTokenAmount,
        uint256 _makerTokenAmount,
        bool _fullOrKill
    ) internal returns (bytes32 orderHash, uint256 takerSpendingAmount, uint256 makerSpendingAmount) {
        uint256 orderFilledAmount;
        (orderHash, orderFilledAmount) = _validateOrder(_order, _makerSignature);

        // get the quote of the fill
        uint256 orderAvailableAmount = _order.makerTokenAmount - orderFilledAmount;
        if (_makerTokenAmount > orderAvailableAmount) {
            // the requested amount is larger than fillable amount
            if (_fullOrKill) revert NotEnoughForFill();

            // take the rest of this order
            makerSpendingAmount = orderAvailableAmount;

            // re-calculate the amount of taker willing to spend for this trade by the requested ratio
            _takerTokenAmount = ((_takerTokenAmount * makerSpendingAmount) / _makerTokenAmount);
        } else {
            // the requested amount can be statisfied
            makerSpendingAmount = _makerTokenAmount;
        }
        uint256 minTakerTokenAmount = ((makerSpendingAmount * _order.takerTokenAmount) / _order.makerTokenAmount);
        // check if taker provide enough amount for this fill (better price is allowed)
        if (_takerTokenAmount < minTakerTokenAmount) revert InvalidTakingAmount();
        takerSpendingAmount = _takerTokenAmount;

        if (takerSpendingAmount == 0) {
            if (makerSpendingAmount == 0) revert ZeroTokenAmount();
        }

        // record fill amount of this tx
        orderHashToMakerTokenFilledAmount[orderHash] = orderFilledAmount + makerSpendingAmount;
    }

    function _validateOrder(LimitOrder calldata _order, bytes calldata _makerSignature) private view returns (bytes32, uint256) {
        // validate the constrain of the order
        if (_order.expiry < block.timestamp) revert ExpiredOrder();
        if (_order.taker != address(0)) {
            if (msg.sender != _order.taker) revert InvalidTaker();
        }

        // validate the status of the order
        bytes32 orderHash = getLimitOrderHash(_order);

        // check whether the order is fully filled or not
        uint256 orderFilledAmount = orderHashToMakerTokenFilledAmount[orderHash];
        // validate maker signature only once per order
        if (orderFilledAmount == 0) {
            if (!SignatureValidator.validateSignature(_order.maker, getEIP712Hash(orderHash), _makerSignature)) revert InvalidSignature();
        }

        if ((orderFilledAmount & ORDER_CANCEL_AMOUNT_MASK) != 0) revert CanceledOrder();
        if (orderFilledAmount >= _order.makerTokenAmount) revert FilledOrder();

        return (orderHash, orderFilledAmount);
    }

    function _emitLimitOrderFilled(
        LimitOrder calldata _order,
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
