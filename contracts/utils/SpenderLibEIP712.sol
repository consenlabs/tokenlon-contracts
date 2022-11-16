// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library SpenderLibEIP712 {
    struct SpendWithPermit {
        address tokenAddr;
        address requester;
        address user;
        address recipient;
        uint256 amount;
        bytes32 actionHash;
        uint64 expiry;
    }
    /*
        keccak256(
            abi.encodePacked(
                "SpendWithPermit(",
                "address tokenAddr,",
                "address requester,",
                "address user,",
                "address recipient,",
                "uint256 amount,",
                "bytes32 actionHash,",
                "uint64 expiry",
                ")"
            )
        );
    */
    uint256 public constant SPEND_WITH_PERMIT_TYPEHASH = 0x52718c957261b99fd72e63478d85d1267cdc812e8249f5a2623566c1818e1ed0;

    function _getSpendWithPermitHash(SpendWithPermit memory _spendWithPermit) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SPEND_WITH_PERMIT_TYPEHASH,
                    _spendWithPermit.tokenAddr,
                    _spendWithPermit.requester,
                    _spendWithPermit.user,
                    _spendWithPermit.recipient,
                    _spendWithPermit.amount,
                    _spendWithPermit.actionHash,
                    _spendWithPermit.expiry
                )
            );
    }
}
