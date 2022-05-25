pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../utils/RFQLibEIP712.sol";
import "./ISetAllowance.sol";

interface IRFQ is ISetAllowance {
    function fill(
        RFQLibEIP712.Order memory _order,
        bytes memory _mmSignature,
        bytes memory _userSignature
    ) external payable returns (uint256);
}
