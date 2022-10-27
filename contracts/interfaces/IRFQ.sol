// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/RFQLibEIP712.sol";
import "../utils/SpenderLibEIP712.sol";

interface IRFQ is IStrategyBase {
    function fill(
        RFQLibEIP712.Order calldata _order,
        bytes calldata _mmSignature,
        bytes calldata _userSignature,
        bytes calldata _makerAssetPermitSig,
        bytes calldata _takerAssetPermitSig
    ) external payable returns (uint256);
}
