// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library AMMLibEIP712 {
    struct Order {
        address makerAddr;
        address takerAssetAddr;
        address makerAssetAddr;
        uint256 takerAssetAmount;
        uint256 makerAssetAmount;
        address userAddr;
        address payable receiverAddr;
        uint256 salt;
        uint256 deadline;
    }

    bytes32 public constant TRADE_WITH_PERMIT_TYPEHASH = 0x213bb100dae8406fe07494ce25c2bfdb417aafdf4a6df7355a70d2d48823c418;

    /*
        keccak256(
            abi.encodePacked(
                "tradeWithPermit(",
                "address makerAddr,",
                "address takerAssetAddr,",
                "address makerAssetAddr,",
                "uint256 takerAssetAmount,",
                "uint256 makerAssetAmount,",
                "address userAddr,",
                "address receiverAddr,",
                "uint256 salt,",
                "uint256 deadline",
                ")"
            )
        );
        */

    function _getOrderHash(Order memory _order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TRADE_WITH_PERMIT_TYPEHASH,
                    _order.makerAddr,
                    _order.takerAssetAddr,
                    _order.makerAssetAddr,
                    _order.takerAssetAmount,
                    _order.makerAssetAmount,
                    _order.userAddr,
                    _order.receiverAddr,
                    _order.salt,
                    _order.deadline
                )
            );
    }
}
