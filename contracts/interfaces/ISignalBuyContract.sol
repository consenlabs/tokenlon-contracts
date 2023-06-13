// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../utils/SignalBuyContractLibEIP712.sol";

/// @title ISignalBuyContract Interface
/// @author imToken Labs
interface ISignalBuyContract {
    /// @notice Emitted when coordinator address is updated
    /// @param newCoordinator The address of the new coordinator
    event UpgradeCoordinator(address newCoordinator);

    /// @notice Emitted when fee factors are updated
    /// @param userFeeFactor The new fee factor for user
    event FactorsUpdated(uint16 userFeeFactor);

    /// @notice Emitted when fee collector address is updated
    /// @param newFeeCollector The address of the new fee collector
    event SetFeeCollector(address newFeeCollector);

    /// @notice Emitted when an order is filled by dealer
    /// @param orderHash The EIP-712 hash of the target order
    /// @param user The address of the user
    /// @param dealer The address of the dealer
    /// @param allowFillHash The EIP-712 hash of the fill permit granted by coordinator
    /// @param recipient The address of the recipient which will receive tokens from user
    /// @param fillReceipt Contains details of this single fill
    event SignalBuyFilledByTrader(
        bytes32 indexed orderHash,
        address indexed user,
        address indexed dealer,
        bytes32 allowFillHash,
        address recipient,
        FillReceipt fillReceipt
    );

    /// @notice Emitted when order is cancelled
    /// @param orderHash The EIP-712 hash of the target order
    /// @param user The address of the user
    event OrderCancelled(bytes32 orderHash, address user);

    struct FillReceipt {
        address userToken;
        address dealerToken;
        uint256 userTokenFilledAmount;
        uint256 dealerTokenFilledAmount;
        uint256 remainingUserTokenAmount;
        uint256 tokenlonFee;
        uint256 dealerFee;
    }

    struct CoordinatorParams {
        bytes sig;
        uint256 salt;
        uint64 expiry;
    }

    struct TraderParams {
        address dealer;
        address recipient;
        uint256 userTokenAmount;
        uint256 dealerTokenAmount;
        uint16 gasFeeFactor;
        uint16 dealerStrategyFeeFactor;
        uint256 salt;
        uint64 expiry;
        bytes dealerSig;
    }

    /// @notice Fill an order by a trader
    /// @notice Only user proxy can call
    /// @param _order The order that is going to be filled
    /// @param _orderUserSig The signature of the order from user
    /// @param _params Trader specific filling parameters
    /// @param _crdParams Contains details of the fill permit
    function fillSignalBuy(
        SignalBuyContractLibEIP712.Order calldata _order,
        bytes calldata _orderUserSig,
        TraderParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external returns (uint256, uint256);

    /// @notice Cancel an order
    /// @notice Only user proxy can call
    /// @param _order The order that is going to be cancelled
    /// @param _cancelUserSig The cancelling signature signed by user
    function cancelSignalBuy(SignalBuyContractLibEIP712.Order calldata _order, bytes calldata _cancelUserSig) external;
}
