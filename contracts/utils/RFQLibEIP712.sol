// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

library RFQLibEIP712 {
    /***********************************|
    |             Constants             |
    |__________________________________*/

    struct Order {
        address takerAddr;
        address makerAddr;
        address takerAssetAddr;
        address makerAssetAddr;
        uint256 takerAssetAmount;
        uint256 makerAssetAmount;
        address receiverAddr;
        uint256 salt;
        uint256 deadline;
        uint256 feeFactor;
    }

    bytes32 public constant ORDER_TYPEHASH = 0xad84a47ecda74707b63cf430860b59806332525ed81c01c6e3ec66983c35646a;

    /*
        keccak256(
            abi.encodePacked(
                "Order(",
                "address takerAddr,",
                "address makerAddr,",
                "address takerAssetAddr,",
                "address makerAssetAddr,",
                "uint256 takerAssetAmount,",
                "uint256 makerAssetAmount,",
                "uint256 salt,",
                "uint256 deadline,",
                "uint256 feeFactor",
                ")"
            )
        );
        */

    function _getOrderHash(Order memory _order) internal pure returns (bytes32 orderHash) {
        orderHash = keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                _order.takerAddr,
                _order.makerAddr,
                _order.takerAssetAddr,
                _order.makerAssetAddr,
                _order.takerAssetAmount,
                _order.makerAssetAmount,
                _order.salt,
                _order.deadline,
                _order.feeFactor
            )
        );
    }

    bytes32 public constant FILL_WITH_PERMIT_TYPEHASH = 0x4ea663383968865a4516f51bec2c29addd1e7cecce5583296a44cc8d568cad09;

    /*
        keccak256(
            abi.encodePacked(
                "fillWithPermit(",
                "address makerAddr,",
                "address takerAssetAddr,",
                "address makerAssetAddr,",
                "uint256 takerAssetAmount,",
                "uint256 makerAssetAmount,",
                "address takerAddr,",
                "address receiverAddr,",
                "uint256 salt,",
                "uint256 deadline,",
                "uint256 feeFactor",
                ")"
            )
        );
        */

    function _getTransactionHash(Order memory _order) internal pure returns (bytes32 transactionHash) {
        transactionHash = keccak256(
            abi.encode(
                FILL_WITH_PERMIT_TYPEHASH,
                _order.makerAddr,
                _order.takerAssetAddr,
                _order.makerAssetAddr,
                _order.takerAssetAmount,
                _order.makerAssetAmount,
                _order.takerAddr,
                _order.receiverAddr,
                _order.salt,
                _order.deadline,
                _order.feeFactor
            )
        );
    }
}
