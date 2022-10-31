// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IStrategyBase.sol";
import "../utils/LimitOrderLibEIP712.sol";

/// @title ILimitOrder Interface
/// @author imToken Labs
interface ILimitOrder is IStrategyBase {
    /// @notice Emitted when coordinator address is updated
    /// @param newCoordinator The address of the new coordinator
    event UpgradeCoordinator(address newCoordinator);

    /// @notice Emitted when fee factors are updated
    /// @param makerFeeFactor The new fee factor for maker
    /// @param takerFeeFactor The new fee factor for taker
    /// @param profitFeeFactor The new fee factor for relayer profit
    event FactorsUpdated(uint16 makerFeeFactor, uint16 takerFeeFactor, uint16 profitFeeFactor);

    /// @notice Emitted when fee collector address is updated
    /// @param newFeeCollector The address of the new fee collector
    event SetFeeCollector(address newFeeCollector);

    /// @notice Emitted when an order is filled by a trader
    /// @param orderHash The EIP-712 hash of the target order
    /// @param maker The address of the maker
    /// @param taker The address of the taker (trader)
    /// @param allowFillHash The EIP-712 hash of the fill permit granted by coordinator
    /// @param recipient The address of the recipient which will receive tokens from maker
    /// @param fillReceipt Contains details of this single fill
    event LimitOrderFilledByTrader(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        bytes32 allowFillHash,
        address recipient,
        FillReceipt fillReceipt
    );

    /// @notice Emitted when an order is filled by interacting with an external protocol
    /// @param orderHash The EIP-712 hash of the target order
    /// @param maker The address of the maker
    /// @param taker The address of the taker (trader)
    /// @param allowFillHash The EIP-712 hash of the fill permit granted by coordinator
    /// @param relayer The address of the relayer
    /// @param profitRecipient The address of the recipient which receives relaying profit
    /// @param fillReceipt Contains details of this single fill
    /// @param relayerTakerTokenProfit Profit that relayer makes from this fill
    /// @param relayerTakerTokenProfitFee Protocol fee charged on the relaying profit
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

    /// @notice Emitted when order is cancelled
    /// @param orderHash The EIP-712 hash of the target order
    /// @param maker The address of the maker
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

    /// @notice Fill an order by a trader
    /// @notice Called by user proxy only
    /// @param _order The order that is going to be filled
    /// @param _orderMakerSig The signature of the order from maker
    /// @param _params Trader specific filling parameters
    /// @param _crdParams Contains details of the fill permit
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

    /// @notice Fill an order by interacting with an external protocol
    /// @notice Called by user proxy only
    /// @param _order The order that is going to be filled
    /// @param _orderMakerSig The signature of the order from maker
    /// @param _params Protocol specific filling parameters
    /// @param _crdParams Contains details of the fill permit
    function fillLimitOrderByProtocol(
        LimitOrderLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        ProtocolParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external returns (uint256);

    /// @notice Cancel an order
    /// @notice Called by user proxy only
    /// @param _order The order that is going to be canceled
    /// @param _cancelMakerSig The canceling signature signed by maker
    function cancelLimitOrder(LimitOrderLibEIP712.Order calldata _order, bytes calldata _cancelMakerSig) external;
}
