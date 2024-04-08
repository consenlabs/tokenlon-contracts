// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IConditionalSwap } from "./interfaces/IConditionalSwap.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";
import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";
import { ConOrder, getConOrderHash } from "./libraries/ConditionalOrder.sol";

/// @title ConditionalSwap Contract
/// @author imToken Labs
contract ConditionalSwap is IConditionalSwap, Ownable, TokenCollector, EIP712 {
    using Asset for address;

    uint256 private constant FLG_SINGLE_AMOUNT_CAP_MASK = 1 << 255; // ConOrder.amount is the cap of single execution, not total cap
    uint256 private constant FLG_PERIODIC_MASK = 1 << 254; // ConOrder can be executed periodically
    uint256 private constant FLG_PARTIAL_FILL_MASK = 1 << 253; // ConOrder can be fill partially
    uint256 private constant PERIOD_MASK = (1 << 128) - 1; // this is a 128-bit mask where all bits are set to 1

    // record how many taker tokens have been filled in an order
    mapping(bytes32 => uint256) public orderHashToTakerTokenFilledAmount;
    mapping(bytes32 => uint256) public orderHashToLastExecutedTime;
    mapping(address => mapping(address => bool)) public makerToRelayer;

    constructor(address _owner, address _uniswapPermit2, address _allowanceTarget) Ownable(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {}

    //@note if this contract has the ability to transfer out ETH, implement the receive function
    // receive() external {}

    function fillConOrder(
        ConOrder calldata order,
        bytes calldata takerSignature,
        uint256 takerTokenAmount,
        uint256 makerTokenAmount,
        bytes calldata settlementData
    ) external payable override {
        if (block.timestamp > order.expiry) revert ExpiredOrder();
        if (msg.sender != order.maker && !makerToRelayer[order.maker][msg.sender]) revert NotOrderExecutor();
        if (order.recipient == address(0)) revert InvalidRecipient();
        if (takerTokenAmount == 0) revert ZeroTokenAmount();

        // validate takerSignature
        bytes32 orderHash = getConOrderHash(order);
        if (orderHashToTakerTokenFilledAmount[orderHash] == 0) {
            if (!SignatureValidator.validateSignature(order.taker, getEIP712Hash(orderHash), takerSignature)) {
                revert InvalidSignature();
            }
        }

        // validate the takerTokenAmount
        if (order.flagsAndPeriod & FLG_SINGLE_AMOUNT_CAP_MASK != 0) {
            // single cap amount
            if (takerTokenAmount > order.takerTokenAmount) revert InvalidTakingAmount();
        } else {
            // total cap amount
            if (orderHashToTakerTokenFilledAmount[orderHash] + takerTokenAmount > order.takerTokenAmount) {
                revert InvalidTakingAmount();
            }
        }
        orderHashToTakerTokenFilledAmount[orderHash] += takerTokenAmount;

        // validate the makerTokenAmounts
        uint256 minMakerTokenAmount;
        if (order.flagsAndPeriod & FLG_PARTIAL_FILL_MASK != 0) {
            // support partial fill
            minMakerTokenAmount = (takerTokenAmount * order.makerTokenAmount) / order.takerTokenAmount;
        } else {
            if (takerTokenAmount != order.takerTokenAmount) revert InvalidTakingAmount();
            minMakerTokenAmount = order.makerTokenAmount;
        }
        if (makerTokenAmount < minMakerTokenAmount) revert InvalidMakingAmount();

        // validate time constrain
        if (order.flagsAndPeriod & FLG_PERIODIC_MASK != 0) {
            uint256 duration = order.flagsAndPeriod & PERIOD_MASK;
            if (block.timestamp - orderHashToLastExecutedTime[orderHash] < duration) revert InsufficientTimePassed();
            orderHashToLastExecutedTime[orderHash] = block.timestamp;
        }

        bytes1 settlementType = settlementData[0];
        bytes memory strategyData = settlementData[1:];

        uint256 returnedAmount;
        if (settlementType == 0x0) {
            // direct settlement type
            returnedAmount = makerTokenAmount;

            _collect(order.takerToken, order.taker, msg.sender, takerTokenAmount, order.takerTokenPermit);
            _collect(order.makerToken, msg.sender, order.recipient, makerTokenAmount, order.takerTokenPermit);
        } else if (settlementType == 0x01) {
            // strategy settlement type
            (address strategy, bytes memory data) = abi.decode(strategyData, (address, bytes));
            _collect(order.takerToken, order.taker, strategy, takerTokenAmount, order.takerTokenPermit);

            uint256 makerTokenBalanceBefore = order.makerToken.getBalance(address(this));
            //@todo Create a separate strategy contract specifically for conditionalSwap
            IStrategy(strategy).executeStrategy(order.takerToken, order.makerToken, takerTokenAmount, data);
            returnedAmount = order.makerToken.getBalance(address(this)) - makerTokenBalanceBefore;

            // We only compare returnedAmount with makerTokenAmount here
            // because we ensure that makerTokenAmount is greater than minMakerTokenAmount before
            if (returnedAmount < makerTokenAmount) revert InsufficientOutput();
            order.makerToken.transferTo(order.recipient, returnedAmount);
        } else revert InvalidSettlementType();

        _emitConOrderFilled(order, orderHash, takerTokenAmount, returnedAmount);
    }

    function addRelayers(address[] calldata relayers) external {
        // the relayers is stored in calldata, there is no need to cache the relayers length
        for (uint256 i; i < relayers.length; ++i) {
            makerToRelayer[msg.sender][relayers[i]] = true;
            emit AddRelayer(msg.sender, relayers[i]);
        }
    }

    function removeRelayers(address[] calldata relayers) external {
        // the relayers is stored in calldata, there is no need to cache the relayers length
        for (uint256 i; i < relayers.length; ++i) {
            delete makerToRelayer[msg.sender][relayers[i]];
            emit RemoveRelayer(msg.sender, relayers[i]);
        }
    }

    function _emitConOrderFilled(ConOrder calldata order, bytes32 orderHash, uint256 takerTokenSettleAmount, uint256 makerTokenSettleAmount) internal {
        emit ConditionalOrderFilled(
            orderHash,
            order.taker,
            order.maker,
            order.takerToken,
            takerTokenSettleAmount,
            order.makerToken,
            makerTokenSettleAmount,
            order.recipient
        );
    }
}
