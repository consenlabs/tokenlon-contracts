// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "./ISetAllowance.sol";

interface IPMM is ISetAllowance {
    function fill(
        uint256 userSalt,
        bytes memory data,
        bytes memory userSignature
    ) external payable returns (uint256);
}
