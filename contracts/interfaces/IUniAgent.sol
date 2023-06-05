// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IUniAgent Interface
/// @author imToken Labs
interface IUniAgent {
    error ZeroAddress();
    error InvalidMsgValue();
    error UnknownRouterType();

    event Swap(address indexed user, address indexed router, address indexed inputToken, uint256 inputAmount);

    enum RouterType {
        V2Router,
        V3Router,
        UniversalRouter
    }

    function swap(
        RouterType routerType,
        address inputToken,
        uint256 inputAmount,
        bytes calldata payload,
        bytes calldata userPermit
    ) external payable;
}
