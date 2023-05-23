// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IStrategyBase.sol";
import "../utils/PionexContractLibEIP712.sol";

/// @title IPionexContract Interface
/// @author imToken Labs
interface IPionexContract is IStrategyBase {
    /// @notice Emitted when coordinator address is updated
    /// @param newCoordinator The address of the new coordinator
    event UpgradeCoordinator(address newCoordinator);

    /// @notice Emitted when fee factors are updated
    /// @param makerFeeFactor The new fee factor for maker
    event FactorsUpdated(uint16 makerFeeFactor);

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
        uint256 tokenlonFee;
        uint256 pionexFee;
    }

    struct CoordinatorParams {
        bytes sig;
        uint256 salt;
        uint64 expiry;
    }

    struct TraderParams {
        address taker;
        address recipient;
        uint256 makerTokenAmount;
        uint256 takerTokenAmount;
        uint16 gasFeeFactor;
        uint16 pionexStrategyFeeFactor;
        uint256 salt;
        uint64 expiry;
        bytes takerSig;
    }

    /// @notice Fill an order by a trader
    /// @notice Only user proxy can call
    /// @param _order The order that is going to be filled
    /// @param _orderMakerSig The signature of the order from maker
    /// @param _params Trader specific filling parameters
    /// @param _crdParams Contains details of the fill permit
    function fillLimitOrderByTrader(
        PionexContractLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        TraderParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external returns (uint256, uint256);

    /// @notice Cancel an order
    /// @notice Only user proxy can call
    /// @param _order The order that is going to be cancelled
    /// @param _cancelMakerSig The cancelling signature signed by maker
    function cancelLimitOrder(PionexContractLibEIP712.Order calldata _order, bytes calldata _cancelMakerSig) external;
}
