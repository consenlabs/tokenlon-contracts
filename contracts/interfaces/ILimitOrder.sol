// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IStrategyBase.sol";
import "../utils/LimitOrderLibEIP712.sol";

/// @title ILimitOrder Interface
/// @author imToken Labs
interface ILimitOrder is IStrategyBase {
    /// @notice emitted when coordinator address is updated
    /// @param newCoordinator the address of the new coordinator
    event UpgradeCoordinator(address newCoordinator);

    /// @notice emitted when fee factors is updated
    /// @param makerFeeFactor the new fee factor for maker
    /// @param takerFeeFactor the new fee factor for taker
    /// @param profitFeeFactor the new fee factor for relayer profit
    event FactorsUpdated(uint16 makerFeeFactor, uint16 takerFeeFactor, uint16 profitFeeFactor);

    /// @notice emitted when fee factors is updated
    /// @param newFeeCollector the address of the new fee collector
    event SetFeeCollector(address newFeeCollector);

    /// @notice emitted when an order is filled by a trader
    /// @param orderHash the EIP-712 hash of the target order
    /// @param maker the address of the maker
    /// @param taker the address of the taker (trader)
    /// @param allowFillHash the EIP-712 hash of the fill permit granted by coordinator
    /// @param recipient the address of the recipient which will receive tokens from maker
    /// @param fillReceipt contains details of this single fill
    event LimitOrderFilledByTrader(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        bytes32 allowFillHash,
        address recipient,
        FillReceipt fillReceipt
    );

    /// @notice emitted when an order is filled by interacting with an external protocol
    /// @param orderHash the EIP-712 hash of the target order
    /// @param maker the address of the maker
    /// @param taker the address of the taker (trader)
    /// @param allowFillHash the EIP-712 hash of the fill permit granted by coordinator
    /// @param relayer the address of the relayer
    /// @param profitRecipient the address of the recipient which receive profit for relayer
    /// @param fillReceipt contains details of this single fill
    /// @param relayerTakerTokenProfit profit that relayer makes from this fill
    /// @param relayerTakerTokenProfitFee fee of the relayer profit in this fill
    event LimitOrderFilledByProtocol(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        bytes32 allowFillHash,
        address relayer,
        address profitRecipient,
        FillReceipt fillReceipt,
        uint256 relayerTakerTokenProfit,
        uint256 relayerTakerTokenProfitFee
    );

    /// @notice emitted when order is cancelled
    /// @param orderHash the EIP-712 hash of the target order
    /// @param maker the address of the maker
    event OrderCancelled(bytes32 orderHash, address maker);

    struct FillReceipt {
        address makerToken;
        address takerToken;
        uint256 makerTokenFilledAmount;
        uint256 takerTokenFilledAmount;
        uint256 remainingAmount;
        uint256 makerTokenFee;
        uint256 takerTokenFee;
    }

    struct CoordinatorParams {
        bytes sig;
        uint256 salt;
        uint64 expiry;
    }

    struct TraderParams {
        address taker;
        address recipient;
        uint256 takerTokenAmount;
        uint256 salt;
        uint64 expiry;
        bytes takerSig;
    }

    /// @notice fill an order by a trader
    /// @notice called by user proxy only
    /// @param _order the order that is going to be filled
    /// @param _orderMakerSig the signature of the order from maker
    /// @param _params trader specific filling parameters
    /// @param _crdParams contains details of the fill permit
    function fillLimitOrderByTrader(
        LimitOrderLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        TraderParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external returns (uint256, uint256);

    enum Protocol {
        UniswapV3,
        Sushiswap
    }

    struct ProtocolParams {
        Protocol protocol;
        bytes data;
        address profitRecipient;
        uint256 takerTokenAmount;
        uint256 protocolOutMinimum;
        uint64 expiry;
    }

    /// @notice fill an order by interacting with an external protocol
    /// @notice called by user proxy only
    /// @param _order the order that is going to be filled
    /// @param _orderMakerSig the signature of the order from maker
    /// @param _params protocol specific filling parameters
    /// @param _crdParams contains details of the fill permit
    function fillLimitOrderByProtocol(
        LimitOrderLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        ProtocolParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external returns (uint256);

    /// @notice cancel an order
    /// @notice called by user proxy only
    /// @param _order the order that is going to be canceled
    /// @param _cancelMakerSig the canceling signature signed by maker
    function cancelLimitOrder(LimitOrderLibEIP712.Order calldata _order, bytes calldata _cancelMakerSig) external;
}
