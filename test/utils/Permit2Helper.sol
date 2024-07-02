// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IUniswapPermit2 } from "contracts/interfaces/IUniswapPermit2.sol";
import { TokenCollector } from "contracts/abstracts/TokenCollector.sol";
import { getEIP712Hash } from "test/utils/Sig.sol";
import { Test } from "forge-std/Test.sol";

contract Permit2Helper is Test {
    IUniswapPermit2 public constant permit2 = IUniswapPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    bytes32 public constant PERMIT_DETAILS_TYPEHASH = keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 public constant PERMIT_SINGLE_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );
    bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 public constant PERMIT_TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    function getPermitSingleHash(IUniswapPermit2.PermitSingle memory permit) public pure returns (bytes32) {
        bytes32 permitDetailsHash = keccak256(abi.encode(PERMIT_DETAILS_TYPEHASH, permit.details));
        return keccak256(abi.encode(PERMIT_SINGLE_TYPEHASH, permitDetailsHash, permit.spender, permit.sigDeadline));
    }

    function getPermitTransferFromHash(IUniswapPermit2.PermitTransferFrom memory permit, address spender) private pure returns (bytes32) {
        bytes32 structHashTokenPermissions = keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        return keccak256(abi.encode(PERMIT_TRANSFER_FROM_TYPEHASH, structHashTokenPermissions, spender, permit.nonce, permit.deadline));
    }

    function signPermitSingle(uint256 privateKey, IUniswapPermit2.PermitSingle memory permitSingle) public view returns (bytes memory) {
        bytes32 permitSingleHash = getPermitSingleHash(permitSingle);
        bytes32 EIP712SignDigest = getEIP712Hash(permit2.DOMAIN_SEPARATOR(), permitSingleHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signPermitTransferFrom(
        uint256 privateKey,
        IUniswapPermit2.PermitTransferFrom memory permitTransferFrom,
        address spender
    ) public view returns (bytes memory) {
        bytes32 permitTransferFromHash = getPermitTransferFromHash(permitTransferFrom, spender);
        bytes32 EIP712SignDigest = getEIP712Hash(permit2.DOMAIN_SEPARATOR(), permitTransferFromHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function encodeAllowanceTransfer(address owner, IUniswapPermit2.PermitSingle memory permit, bytes memory permitSig) public pure returns (bytes memory) {
        bytes memory permit2Calldata = abi.encode(owner, permit, permitSig);
        return abi.encodePacked(TokenCollector.Source.Permit2AllowanceTransfer, permit2Calldata);
    }

    function encodeSignatureTransfer(IUniswapPermit2.PermitTransferFrom memory permit, bytes memory permitSig) public pure returns (bytes memory) {
        return abi.encodePacked(TokenCollector.Source.Permit2SignatureTransfer, abi.encode(permit.nonce, permit.deadline, permitSig));
    }

    // will return encoded AllownaceTransfer data
    function getTokenlonPermit2Data(address owner, uint256 ownerPrivateKey, address token, address spender) public view returns (bytes memory) {
        uint256 expiration = block.timestamp + 1 days;
        (, , uint48 nonce) = permit2.allowance(owner, token, spender);

        IUniswapPermit2.PermitSingle memory permit = IUniswapPermit2.PermitSingle({
            details: IUniswapPermit2.PermitDetails({ token: token, amount: type(uint160).max, expiration: uint48(expiration), nonce: nonce }),
            spender: spender,
            sigDeadline: expiration
        });
        bytes memory permitSig = signPermitSingle(ownerPrivateKey, permit);
        return encodeAllowanceTransfer(owner, permit, permitSig);
    }
}
