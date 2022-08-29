// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "../utils/L2DepositLibEIP712.sol";

interface IL2Deposit {
    event CollectArbitrumL2Refund(
        address indexed arbitrumL2RefundCollector,
        uint256 indexed seqNum,
        uint256 indexed amount,
        uint256 maxSubmissionCost,
        uint256 maxGas,
        uint256 gasPriceBid
    );
    event SetArbitrumL2RefundCollector(address newArbitrumL2RefundCollector);
    event UpgradeSpender(address newSpender);
    event Deposited(
        L2DepositLibEIP712.L2Identifier indexed l2Identifier,
        address indexed l1TokenAddr,
        address l2TokenAddr,
        address indexed sender,
        address recipient,
        uint256 amount,
        bytes data,
        bytes bridgeResponse
    );

    struct DepositParams {
        L2DepositLibEIP712.Deposit deposit;
        bytes depositSig;
    }

    function deposit(DepositParams calldata _params) external payable;
}
