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
/// @notice This contract allows users to execute limit orders for token swaps
contract LimitOrderSwap is ILimitOrderSwap, Ownable, TokenCollector, EIP712, ReentrancyGuard {
    using Asset for address;

    /// @dev Mask used to mark order cancellation in `orderHashToMakerTokenFilledAmount`.
    /// The left-most bit (bit 255) of `orderHashToMakerTokenFilledAmount[orderHash]` represents order cancellation.
    uint256 private constant ORDER_CANCEL_AMOUNT_MASK = 1 << 255;

    IWETH public immutable weth;
    address payable public feeCollector;

    /// @notice Mapping to track the filled amounts of maker tokens for each order hash.
    mapping(bytes32 orderHash => uint256 orderFilledAmount) public orderHashToMakerTokenFilledAmount;

    /// @notice Constructor to initialize the contract with the owner, Uniswap permit2, allowance target, WETH, and fee collector.
    /// @param _owner The address of the contract owner.
    /// @param _uniswapPermit2 The address of the Uniswap permit2.
    /// @param _allowanceTarget The address of the allowance target.
    /// @param _weth The WETH token instance.
    /// @param _feeCollector The initial address of the fee collector.
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

    /// @notice Receive function to receive ETH.
    receive() external payable {}

    /// @notice Sets a new fee collector address.
    /// @dev Only the owner can call this function.
    /// @param _newFeeCollector The new address of the fee collector.
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
            if (makingAmount == 0) revert ZeroMakerSpendingAmount();

            (bytes32 orderHash, uint256 orderFilledAmount) = _validateOrder(order, makerSignatures[i]);
            {
                uint256 orderAvailableAmount;
                unchecked {
                    // orderAvailableAmount must be greater than 0 here, or it will be reverted by the _validateOrder function
                    orderAvailableAmount = order.makerTokenAmount - orderFilledAmount;
                }
                if (makingAmount > orderAvailableAmount) revert NotEnoughForFill();
                takerTokenAmounts[i] = ((makingAmount * order.takerTokenAmount) / order.makerTokenAmount);
                if (takerTokenAmounts[i] == 0) revert ZeroTakerTokenAmount();

                // this if statement cannot be covered by tests due to the following issue
                // https://github.com/foundry-rs/foundry/issues/3600
                if (order.takerToken == address(weth)) {
                    wethToPay += takerTokenAmounts[i];
                }

                // record fill amount
                orderHashToMakerTokenFilledAmount[orderHash] = orderFilledAmount + makingAmount;
            }

            // collect maker tokens
            _collect(order.makerToken, order.maker, address(this), makingAmount, order.makerTokenPermit);

            // Transfer fee if present
            uint256 fee = (makingAmount * order.feeFactor) / Constant.BPS_MAX;
            order.makerToken.transferTo(_feeCollector, fee);

            _emitLimitOrderFilled(order, orderHash, takerTokenAmounts[i], makingAmount - fee, fee, address(this));
        }

        // unwrap extra WETH in order to pay for ETH taker token and profit
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > wethToPay) {
            // this if statement cannot be fully covered because the WETH withdraw will always succeed as we have checked that wethBalance > wethToPay
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

    /// @inheritdoc ILimitOrderSwap
    function isOrderCanceled(bytes32 orderHash) external view returns (bool) {
        uint256 orderFilledAmount = orderHashToMakerTokenFilledAmount[orderHash];
        return (orderFilledAmount & ORDER_CANCEL_AMOUNT_MASK) != 0;
    }

    /// @notice Fills a limit order.
    /// @param order The limit order details.
    /// @param makerSignature The maker's signature for the order.
    /// @param takerParams The taker's parameters for the order.
    /// @param fullOrKill Whether the order should be filled completely or not at all.
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
            // the coverage report indicates that the following line causes the if statement to not be fully covered,
            // even if the logic of the executeStrategy function is empty, this if statement is still not covered.
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

    /// @notice Validates an order and quotes the taker and maker spending amounts.
    /// @param _order The limit order details.
    /// @param _makerSignature The maker's signature for the order.
    /// @param _takerTokenAmount The amount of taker token.
    /// @param _makerTokenAmount The amount of maker token.
    /// @param _fullOrKill Whether the order should be filled completely or not at all.
    /// @return orderHash The hash of the validated order.
    /// @return takerSpendingAmount The calculated taker spending amount.
    /// @return makerSpendingAmount The calculated maker spending amount.
    function _validateOrderAndQuote(
        LimitOrder calldata _order,
        bytes calldata _makerSignature,
        uint256 _takerTokenAmount,
        uint256 _makerTokenAmount,
        bool _fullOrKill
    ) internal returns (bytes32 orderHash, uint256 takerSpendingAmount, uint256 makerSpendingAmount) {
        uint256 orderFilledAmount;
        (orderHash, orderFilledAmount) = _validateOrder(_order, _makerSignature);

        if (_takerTokenAmount == 0) revert ZeroTakerSpendingAmount();
        if (_makerTokenAmount == 0) revert ZeroMakerSpendingAmount();

        // get the quote of the fill
        uint256 orderAvailableAmount;
        unchecked {
            // orderAvailableAmount must be greater than 0 here, or it will be reverted by the _validateOrder function
            orderAvailableAmount = _order.makerTokenAmount - orderFilledAmount;
        }

        if (_makerTokenAmount > orderAvailableAmount) {
            // the requested amount is larger than fillable amount
            if (_fullOrKill) revert NotEnoughForFill();

            // take the rest of this order
            makerSpendingAmount = orderAvailableAmount;

            // re-calculate the amount of taker willing to spend for this trade by the requested ratio
            _takerTokenAmount = ((_takerTokenAmount * makerSpendingAmount) / _makerTokenAmount);
            // Check _takerTokenAmount again
            // because there is a case where _takerTokenAmount == 0 after a division calculation
            if (_takerTokenAmount == 0) revert ZeroTakerSpendingAmount();
        } else {
            // the requested amount can be satisfied
            makerSpendingAmount = _makerTokenAmount;
        }
        uint256 minTakerTokenAmount = ((makerSpendingAmount * _order.takerTokenAmount) / _order.makerTokenAmount);
        // check if taker provides enough amount for this fill (better price is allowed)
        if (_takerTokenAmount < minTakerTokenAmount) revert InvalidTakingAmount();
        takerSpendingAmount = _takerTokenAmount;

        // record fill amount of this tx
        orderHashToMakerTokenFilledAmount[orderHash] = orderFilledAmount + makerSpendingAmount;
    }

    /// @notice Validates an order and its signature.
    /// @param _order The limit order details.
    /// @param _makerSignature The maker's signature for the order.
    /// @return orderHash The hash of the validated order.
    /// @return orderFilledAmount The filled amount of the validated order.
    function _validateOrder(LimitOrder calldata _order, bytes calldata _makerSignature) private view returns (bytes32, uint256) {
        // validate the constraints of the order
        if (_order.expiry < block.timestamp) revert ExpiredOrder();
        if (_order.taker != address(0)) {
            if (msg.sender != _order.taker) revert InvalidTaker();
        }
        if (_order.takerTokenAmount == 0) revert ZeroTakerTokenAmount();
        if (_order.makerTokenAmount == 0) revert ZeroMakerTokenAmount();

        bytes32 orderHash = getLimitOrderHash(_order);
        uint256 orderFilledAmount = orderHashToMakerTokenFilledAmount[orderHash];

        if (orderFilledAmount == 0) {
            // validate maker signature only once per order
            if (!SignatureValidator.validateSignature(_order.maker, getEIP712Hash(orderHash), _makerSignature)) revert InvalidSignature();
        }

        // validate the status of the order
        if ((orderFilledAmount & ORDER_CANCEL_AMOUNT_MASK) != 0) revert CanceledOrder();
        // check whether the order is fully filled or not
        if (orderFilledAmount >= _order.makerTokenAmount) revert FilledOrder();

        return (orderHash, orderFilledAmount);
    }

    /// @notice Emits the LimitOrderFilled event after executing a limit order swap.
    /// @param _order The limit order details.
    /// @param _orderHash The hash of the limit order.
    /// @param _takerTokenSettleAmount The settled amount of taker token.
    /// @param _makerTokenSettleAmount The settled amount of maker token.
    /// @param _fee The fee amount.
    /// @param _recipient The recipient of the order settlement.
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
