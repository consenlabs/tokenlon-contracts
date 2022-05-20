// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library SpenderLibEIP712 {
    struct SpendWithPermit {
        address tokenAddr;
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
                "address user,",
                "address recipient,",
                "uint256 amount,",
                "uint256 salt,",
                "uint64 expiry",
                ")"
            )
        );
    */
    uint256 public constant SPEND_WITH_PERMIT_TYPEHASH = 0xef4569e9739cba74d90490d1bd03bf9bb1ce2f4b9134ad0e79ba922a1f70c1a1;

    function _getSpendWithPermitHash(SpendWithPermit memory _spendWithPermit) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    SPEND_WITH_PERMIT_TYPEHASH,
                    _spendWithPermit.tokenAddr,
                    _spendWithPermit.user,
                    _spendWithPermit.recipient,
                    _spendWithPermit.amount,
                    _spendWithPermit.salt,
                    _spendWithPermit.expiry
                )
            );
    }
}
