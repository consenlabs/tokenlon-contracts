// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { TokenCollector } from "contracts/utils/TokenCollector.sol";

bytes32 constant PERMIT_DETAILS_TYPEHASH = keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
bytes32 constant PERMIT_SINGLE_TYPEHASH = keccak256(
    "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
);

bytes32 constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
bytes32 constant PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
    "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
);

function getPermitSingleStructHash(IUniswapPermit2.PermitSingle memory permit) pure returns (bytes32) {
    bytes32 structHashPermitDetails = keccak256(abi.encode(PERMIT_DETAILS_TYPEHASH, permit.details));
    return keccak256(abi.encode(PERMIT_SINGLE_TYPEHASH, structHashPermitDetails, permit.spender, permit.sigDeadline));
}

function encodePermitSingleData(IUniswapPermit2.PermitSingle memory permit, bytes memory permitSig) pure returns (bytes memory) {
    return abi.encode(TokenCollector.Source.Permit2AllowanceTransfer, abi.encode(permit.details.nonce, permit.details.expiration, permitSig));
}

function getPermitTransferFromStructHash(IUniswapPermit2.PermitTransferFrom memory permit, address spender) pure returns (bytes32) {
    bytes32 structHashTokenPermissions = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
    return keccak256(abi.encode(PERMIT_TRANSFER_FROM_TYPEHASH, structHashTokenPermissions, spender, permit.nonce, permit.deadline));
}

function encodePermitTransferFromData(IUniswapPermit2.PermitTransferFrom memory permit, bytes memory permitSig) pure returns (bytes memory) {
    return abi.encode(TokenCollector.Source.Permit2SignatureTransfer, abi.encode(permit.nonce, permit.deadline, permitSig));
}
