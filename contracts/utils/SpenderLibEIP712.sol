// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library SpenderLibEIP712 {
    struct SpendWithPermit {
        address tokenAddr;
        address requester;
        address user;
        address recipient;
        uint256 amount;
        bytes32 txHash;
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
                "bytes32 txHash,",
                "uint64 expiry",
                ")"
            )
        );
    */
    uint256 public constant SPEND_WITH_PERMIT_TYPEHASH = 0x356b0c4ef9d6005a11dc7bead0f1cea62bd30d1e5d59c407e9a7c13f54b24970;

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
                    _spendWithPermit.txHash,
                    _spendWithPermit.expiry
                )
            );
    }
}
