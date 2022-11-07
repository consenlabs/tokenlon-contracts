// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/L2DepositLibEIP712.sol";

interface IL2Deposit is IStrategyBase {
    /// @notice Emitted when deposit tokens to L2 successfully
    /// @param l2Identifier The identifier of which L2 chain the deposit is sent to
    /// @param l1TokenAddr The token contract address on L1
    /// @param l2TokenAddr The token contract address on L2
    /// @param sender The sender's address on L1
    /// @param recipient The recipient's address on L2
    /// @param amount The amount of token to be sent
    /// @param data The specific data related to different L2
    /// @param bridgeResponse The response from L2 bridge
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

    /// @notice Deposit user's fund into L2 bridge
    /// @param _params The deposit data that sends token to L2
    function deposit(DepositParams calldata _params) external payable;
}
