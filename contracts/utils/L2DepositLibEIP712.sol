// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library L2DepositLibEIP712 {
    enum L2Identifier {
        Arbitrum,
        Optimism
    }

    struct Deposit {
        L2Identifier l2Identifier;
        address l1TokenAddr;
        address l2TokenAddr;
        address sender;
        address recipient;
        uint256 amount;
        uint256 salt;
        uint256 expiry;
        bytes data;
    }
    /*
        keccak256(
            abi.encodePacked(
                "Deposit(",
                "uint8 l2Identifier,",
                "address l1TokenAddr,",
                "address l2TokenAddr,",
                "address sender,",
                "address recipient,",
                "uint256 amount,",
                "uint256 salt,",
                "uint256 expiry,",
                "bytes data",
                ")"
            )
        );
    */
    uint256 public constant DEPOSIT_TYPEHASH = 0xcb01777a6a26e7a311d06c0d9a55950903d8d51be8a9b7d62cc1b6099cda5a1c;

    function _getDepositHash(Deposit memory _deposit) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DEPOSIT_TYPEHASH,
                    _deposit.l2Identifier,
                    _deposit.l1TokenAddr,
                    _deposit.l2TokenAddr,
                    _deposit.sender,
                    _deposit.recipient,
                    _deposit.amount,
                    _deposit.salt,
                    _deposit.expiry,
                    keccak256(_deposit.data)
                )
            );
    }
}
