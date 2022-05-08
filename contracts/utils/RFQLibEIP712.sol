pragma solidity 0.7.6;

import "./BaseLibEIP712.sol";
import "./SignatureValidator.sol";

contract RFQLibEIP712 is BaseLibEIP712 {
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

    bytes32 public constant ORDER_TYPEHASH =
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

    function _getOrderSignDigest(Order memory _order) internal view returns (bytes32 orderSignDigest) {
        orderSignDigest = keccak256(abi.encodePacked(EIP191_HEADER, EIP712_DOMAIN_SEPARATOR, _getOrderHash(_order)));
    }

    function _getOrderSignDigestFromHash(bytes32 _orderHash) internal view returns (bytes32 orderSignDigest) {
        orderSignDigest = keccak256(abi.encodePacked(EIP191_HEADER, EIP712_DOMAIN_SEPARATOR, _orderHash));
    }

    bytes32 public constant FILL_WITH_PERMIT_TYPEHASH =
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

    function _getTransactionSignDigest(Order memory _order) internal view returns (bytes32 transactionSignDigest) {
        transactionSignDigest = keccak256(abi.encodePacked(EIP191_HEADER, EIP712_DOMAIN_SEPARATOR, _getTransactionHash(_order)));
    }

    function _getTransactionSignDigestFromHash(bytes32 _txHash) internal view returns (bytes32 transactionSignDigest) {
        transactionSignDigest = keccak256(abi.encodePacked(EIP191_HEADER, EIP712_DOMAIN_SEPARATOR, _txHash));
    }
}
