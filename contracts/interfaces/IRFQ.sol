// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/RFQLibEIP712.sol";

interface IRFQ is IStrategyBase {
    struct SpendOption {
        bool useSpenderForMaker;
    }

    function fill(
        RFQLibEIP712.Order calldata _order,
        bytes calldata _mmSignature,
        bytes calldata _userSignature
    ) external payable returns (uint256);

    function fillWithSpendOption(
        RFQLibEIP712.Order calldata _order,
        bytes calldata _mmSignature,
        bytes calldata _userSignature,
        SpendOption calldata _spendOption
    ) external payable returns (uint256);
}
