// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/AMMLibEIP712.sol";

interface IAMMWrapper is IStrategyBase {
    // Operator events
    event SetDefaultFeeFactor(uint16 newDefaultFeeFactor);
    event SetFeeCollector(address newFeeCollector);

    event Swapped(
        string source,
        bytes32 indexed transactionHash,
        address indexed userAddr,
        bool relayed,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );

    // Group the local variables together to prevent stack too deep error.
    struct TxMetaData {
        string source;
        bytes32 transactionHash;
        uint256 settleAmount;
        uint256 receivedAmount;
        uint16 feeFactor;
        bool relayed;
    }

    function trade(
        AMMLibEIP712.Order calldata _order,
        uint256 _feeFactor,
        bytes calldata _sig,
        bytes calldata _takerAssetPermitSig
    ) external payable returns (uint256);
}
