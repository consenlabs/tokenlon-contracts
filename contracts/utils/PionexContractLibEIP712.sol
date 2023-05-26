// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IPionexContract.sol";

library PionexContractLibEIP712 {
    struct Order {
        IERC20 userToken;
        IERC20 pionexToken;
        uint256 userTokenAmount;
        uint256 minPionexTokenAmount;
        address user;
        address pionex;
        uint256 salt;
        uint64 expiry;
    }

    /*
        keccak256(
            abi.encodePacked(
                "Order(",
                "address userToken,",
                "address pionexToken,",
                "uint256 userTokenAmount,",
                "uint256 minPionexTokenAmount,",
                "address user,",
                "address pionex,",
                "uint256 salt,",
                "uint64 expiry",
                ")"
            )
        );
    */
    bytes32 private constant ORDER_TYPEHASH = 0xc3eca7f47a388a29b03acba9184de40640fb7d9394cc3ef572b90c15c2f34feb;

    function _getOrderStructHash(Order memory _order) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    address(_order.userToken),
                    address(_order.pionexToken),
                    _order.userTokenAmount,
                    _order.minPionexTokenAmount,
                    _order.user,
                    _order.pionex,
                    _order.salt,
                    _order.expiry
                )
            );
    }

    struct Fill {
        bytes32 orderHash; // EIP712 hash
        address pionex;
        address recipient;
        uint256 userTokenAmount;
        uint256 pionexTokenAmount;
        uint256 pionexSalt;
        uint64 expiry;
    }

    /*
        keccak256(
            abi.encodePacked(
                "Fill(",
                "bytes32 orderHash,",
                "address pionex,",
                "address recipient,",
                "uint256 userTokenAmount,",
                "uint256 pionexTokenAmount,",
                "uint256 pionexSalt,",
                "uint64 expiry",
                ")"
            )
        );
    */
    bytes32 private constant FILL_TYPEHASH = 0x8df856cadbad83b5dc946bdac2a541b74332d7444f83e9794203304034f44166;

    function _getFillStructHash(Fill memory _fill) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    FILL_TYPEHASH,
                    _fill.orderHash,
                    _fill.pionex,
                    _fill.recipient,
                    _fill.userTokenAmount,
                    _fill.pionexTokenAmount,
                    _fill.pionexSalt,
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
