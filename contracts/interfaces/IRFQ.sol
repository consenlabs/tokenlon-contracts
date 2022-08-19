// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./ISetAllowance.sol";
import "../utils/RFQLibEIP712.sol";

interface IRFQ is ISetAllowance {
    function fill(
        RFQLibEIP712.Order memory _order,
        bytes memory _mmSignature,
        bytes memory _userSignature
    ) external payable returns (uint256);
}
