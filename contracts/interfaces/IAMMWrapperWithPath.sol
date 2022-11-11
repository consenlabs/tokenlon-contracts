// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IAMMWrapper.sol";
import "../utils/AMMLibEIP712.sol";

interface IAMMWrapperWithPath is IAMMWrapper {
    // Group the local variables together to prevent
    // Compiler error: Stack too deep, try removing local variables.
    struct TradeWithPathParams {
        AMMLibEIP712.Order order;
        uint256 feeFactor;
        bytes sig;
        bytes takerAssetPermitSig;
        bytes makerSpecificData;
        address[] path;
    }

    function trade(TradeWithPathParams calldata _params) external payable returns (uint256);
}
