// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/L2DepositLibEIP712.sol";

interface IL2Deposit is IStrategyBase {
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

    /// @notice Deposit user's fund into layer2 bridge
    /// @param _params The deposit data following EIP-712 plus the user's signature of it
    function deposit(DepositParams calldata _params) external payable;
}
