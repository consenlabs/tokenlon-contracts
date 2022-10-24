// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IStrategyBase.sol";
import "../utils/RFQLibEIP712.sol";
import "../utils/SpenderLibEIP712.sol";

interface IRFQ is IStrategyBase {
    function fill(
        RFQLibEIP712.Order memory _order,
        SpenderLibEIP712.SpendWithPermit memory _spendMakerAssetToReceiver,
        SpenderLibEIP712.SpendWithPermit memory _spendTakerAssetToMaker,
        bytes memory _mmSignature,
        bytes memory _userSignature,
        bytes memory _spendMakerAssetToReceiverSig,
        bytes memory _spendTakerAssetToMakerSig
    ) external payable returns (uint256);
}
