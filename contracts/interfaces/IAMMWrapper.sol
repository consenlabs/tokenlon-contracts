// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "./ISetAllowance.sol";

interface IAMMWrapper is ISetAllowance {
    // Operator events
    event TransferOwnership(address newOperator);
    event UpgradeSpender(address newSpender);
    event SetDefaultFeeFactor(uint16 newDefaultFeeFactor);
    event AllowTransfer(address spender);
    event DisallowTransfer(address spender);
    event DepositETH(uint256 ethBalance);
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

    // Group the local variables together to prevent
    // Compiler error: Stack too deep, try removing local variables.
    struct TxMetaData {
        string source;
        bytes32 transactionHash;
        uint256 settleAmount;
        uint256 receivedAmount;
        uint16 feeFactor;
        bool relayed;
    }

    function trade(
        address _makerAddress,
        address _fromAssetAddress,
        address _toAssetAddress,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        uint256 _feeFactor,
        address _spender,
        address payable _receiver,
        uint256 _nonce,
        uint256 _deadline,
        bytes memory _sig
    ) external payable returns (uint256);
}
