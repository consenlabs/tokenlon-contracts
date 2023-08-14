// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

string constant ORDER_TYPESTRING = "Order(address userToken,address dealerToken,uint256 userTokenAmount,uint256 minDealerTokenAmount,address user,address dealer,uint256 salt,uint64 expiry)";

bytes32 constant ORDER_TYPEHASH = keccak256(bytes(ORDER_TYPESTRING));

function getOrderStructHash(Order memory _order) pure returns (bytes32) {
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

string constant FILL_TYPESTRING = "Fill(bytes32 orderHash,address dealer,address recipient,uint256 userTokenAmount,uint256 dealerTokenAmount,uint256 dealerSalt,uint64 expiry)";

bytes32 constant FILL_TYPEHASH = keccak256(bytes(FILL_TYPESTRING));

function getFillStructHash(Fill memory _fill) pure returns (bytes32) {
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

string constant ALLOW_FILL_TYPESTRING = "AllowFill(bytes32 orderHash,address executor,uint256 fillAmount,uint256 salt,uint64 expiry)";

bytes32 constant ALLOW_FILL_TYPEHASH = keccak256(bytes(ALLOW_FILL_TYPESTRING));

function getAllowFillStructHash(AllowFill memory _allowFill) pure returns (bytes32) {
    return keccak256(abi.encode(ALLOW_FILL_TYPEHASH, _allowFill.orderHash, _allowFill.executor, _allowFill.fillAmount, _allowFill.salt, _allowFill.expiry));
}
