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
        address arbitrumRefundAddr;
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
                "address arbitrumRefundAddr,",
                "uint256 amount,",
                "uint256 salt,",
                "uint256 expiry,",
                "bytes data",
                ")"
            )
        );
    */
    uint256 public constant DEPOSIT_TYPEHASH = 0x48b4034bf822bee4427761f463833610ff0149fb7ef568ebfe2b8519aad3e507;

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
                    _deposit.arbitrumRefundAddr,
                    _deposit.amount,
                    _deposit.salt,
                    _deposit.expiry,
                    keccak256(_deposit.data)
                )
            );
    }
}
