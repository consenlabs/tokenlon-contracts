// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../utils/LimitOrderLibEIP712.sol";

interface ILimitOrder {
    event TransferOwnership(address newOperator);
    event UpgradeSpender(address newSpender);
    event UpgradeCoordinator(address newCoordinator);
    event AllowTransfer(address spender);
    event DisallowTransfer(address spender);
    event DepositETH(uint256 ethBalance);
    event FactorsUpdated(uint16 makerFeeFactor, uint16 takerFeeFactor, uint16 profitFeeFactor);
    event SetFeeCollector(address newFeeCollector);
    event LimitOrderFilledByTrader(
        bytes32 indexed orderHash,
        address indexed maker,
        address indexed taker,
        bytes32 allowFillHash,
        address recipient,
        FillReceipt fillReceipt
    );
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

    /**
     * Fill limit order by trader
     */
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

    /**
     * Fill limit order by protocol
     */
    function fillLimitOrderByProtocol(
        LimitOrderLibEIP712.Order calldata _order,
        bytes calldata _orderMakerSig,
        ProtocolParams calldata _params,
        CoordinatorParams calldata _crdParams
    ) external returns (uint256);

    /**
     * Cancel limit order
     */
    function cancelLimitOrder(LimitOrderLibEIP712.Order calldata _order, bytes calldata _cancelMakerSig) external;
}
