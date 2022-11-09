// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "forge-std/Test.sol";
import "contracts/Spender.sol";
import "contracts/utils/SpenderLibEIP712.sol";
import "contracts/utils/SignatureValidator.sol";
import { getEIP712Hash } from "contracts-test/utils/Sig.sol";

contract Permit is Test {
    function signSpendWithPermit(
        uint256 privateKey,
        SpenderLibEIP712.SpendWithPermit memory spendWithPermit,
        bytes32 domainSeparator,
        SignatureValidator.SignatureType sigType
    ) internal returns (bytes memory sig) {
        uint256 SPEND_WITH_PERMIT_TYPEHASH = 0x52718c957261b99fd72e63478d85d1267cdc812e8249f5a2623566c1818e1ed0;
        bytes32 structHash = keccak256(
            abi.encode(
                SPEND_WITH_PERMIT_TYPEHASH,
                spendWithPermit.tokenAddr,
                spendWithPermit.requester,
                spendWithPermit.user,
                spendWithPermit.recipient,
                spendWithPermit.amount,
                spendWithPermit.actionHash,
                spendWithPermit.expiry
            )
        );
        bytes32 spendWithPermitHash = getEIP712Hash(domainSeparator, structHash);
        if (sigType == SignatureValidator.SignatureType.Wallet) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toEthSignedMessageHash(spendWithPermitHash));
            sig = abi.encodePacked(r, s, v, uint8(sigType)); // new signature format
        } else {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, spendWithPermitHash);
            sig = abi.encodePacked(r, s, v, uint8(sigType)); // new signature format
        }
    }
}
