// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IUniAgent Interface
/// @author imToken Labs
interface IUniAgent {
    error InvalidMsgValue();

    /// @notice Emitted when a swap is executed
    /// @param user The user address of the swap.
    /// @param router The uniswap router address of the swap.
    /// @param inputToken The input token address of the swap.
    /// @param inputAmount The input amount of the swap.
    event Swap(address indexed user, address indexed router, address indexed inputToken, uint256 inputAmount);

    /// @notice The enum of which uniswap router should be called.
    enum RouterType {
        V2Router,
        V3Router,
        SwapRouter02,
        UniversalRouter
    }

    /// @notice Approve token to router and execute a swap
    /// @param routerType The type of uniswap router should be used.
    /// @param inputToken The input token address of the swap.
    /// @param inputAmount The input amount of the swap.
    /// @param payload The execution payload for uniswap router.
    /// @param userPermit The permit of user for token transfering.
    function approveAndSwap(
        RouterType routerType,
        address inputToken,
        uint256 inputAmount,
        bytes calldata payload,
        bytes calldata userPermit
    ) external payable;

    /// @notice Execute a swap
    /// @param routerType The type of uniswap router should be used.
    /// @param inputToken The input token address of the swap.
    /// @param inputAmount The input amount of the swap.
    /// @param payload The execution payload for uniswap router.
    /// @param userPermit The permit of user for token transfering.
    function swap(
        RouterType routerType,
        address inputToken,
        uint256 inputAmount,
        bytes calldata payload,
        bytes calldata userPermit
    ) external payable;
}
