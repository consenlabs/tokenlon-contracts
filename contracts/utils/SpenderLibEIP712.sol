// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library SpenderLibEIP712 {
    struct SpendWithPermit {
        address tokenAddr;
        address requester;
        address user;
        address recipient;
        uint256 amount;
        uint256 salt;
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
                "uint256 salt,",
                "uint64 expiry",
                ")"
            )
        );
    */
    uint256 public constant SPEND_WITH_PERMIT_TYPEHASH = 0xab1af22032364b17f69bad7eabde29f0cd3f761861c0343407be7fcac2e3ff1f;

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
                    _spendWithPermit.salt,
                    _spendWithPermit.expiry
                )
            );
    }
}
