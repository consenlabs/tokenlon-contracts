// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IPionexContract.sol";

library PionexContractLibEIP712 {
    struct Order {
        IERC20 userToken;
        IERC20 dealerToken;
        uint256 userTokenAmount;
        uint256 minDealerTokenAmount;
        address user;
        address dealer;
        uint256 salt;
        uint64 expiry;
    }

    /*
        keccak256(
            abi.encodePacked(
                "Order(",
                "address userToken,",
                "address dealerToken,",
                "uint256 userTokenAmount,",
                "uint256 minDealerTokenAmount,",
                "address user,",
                "address dealer,",
                "uint256 salt,",
                "uint64 expiry",
                ")"
            )
        );
    */
    bytes32 private constant ORDER_TYPEHASH = 0x2f0bead1a08e744d3b433a8d66c0a8f920a802838bc159ace4322e432f51458d;

    function _getOrderStructHash(Order memory _order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    address(_order.userToken),
                    address(_order.dealerToken),
                    _order.userTokenAmount,
                    _order.minDealerTokenAmount,
                    _order.user,
                    _order.dealer,
                    _order.salt,
                    _order.expiry
                )
            );
    }

    struct Fill {
        bytes32 orderHash; // EIP712 hash
        address dealer;
        address recipient;
        uint256 userTokenAmount;
        uint256 dealerTokenAmount;
        uint256 dealerSalt;
        uint64 expiry;
    }

    /*
        keccak256(
            abi.encodePacked(
                "Fill(",
                "bytes32 orderHash,",
                "address dealer,",
                "address recipient,",
                "uint256 userTokenAmount,",
                "uint256 dealerTokenAmount,",
                "uint256 dealerSalt,",
                "uint64 expiry",
                ")"
            )
        );
    */
    bytes32 private constant FILL_TYPEHASH = 0xd368a73a41233a76912e96676a984799852399878d2dc3ae8ddd0480b42aec88;

    function _getFillStructHash(Fill memory _fill) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    FILL_TYPEHASH,
                    _fill.orderHash,
                    _fill.dealer,
                    _fill.recipient,
                    _fill.userTokenAmount,
                    _fill.dealerTokenAmount,
                    _fill.dealerSalt,
                    _fill.expiry
                )
            );
    }

    struct AllowFill {
        bytes32 orderHash; // EIP712 hash
        address executor;
        uint256 fillAmount;
        uint256 salt;
        uint64 expiry;
    }

    /*
        keccak256(abi.encodePacked("AllowFill(", "bytes32 orderHash,", "address executor,", "uint256 fillAmount,", "uint256 salt,", "uint64 expiry", ")"));
    */
    bytes32 private constant ALLOW_FILL_TYPEHASH = 0xa471a3189b88889758f25ee2ce05f58964c40b03edc9cc9066079fd2b547f074;

    function _getAllowFillStructHash(AllowFill memory _allowFill) internal pure returns (bytes32) {
        return keccak256(abi.encode(ALLOW_FILL_TYPEHASH, _allowFill.orderHash, _allowFill.executor, _allowFill.fillAmount, _allowFill.salt, _allowFill.expiry));
    }
}
