// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/L2DepositLibEIP712.sol";

interface IL2Deposit is IStrategyBase {
    /// @notice This event is emmitted when deposit action to layer2 is done
    /// @param l2Identifier The identifier of which layer2 chain the deposit is send to
    /// @param l1TokenAddr The token contract address on layer1
    /// @param l2TokenAddr The token contract address on layer2
    /// @param sender The sender's address on layer1
    /// @param recipient The recipient's address on layer2
    /// @param amount The amount of token to be sent
    /// @param data The message data of L2Deposit following EIP-712
    /// @param bridgeResponse The response from layer2 bridge
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
