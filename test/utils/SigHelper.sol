// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AllowFill, getAllowFillHash } from "contracts/libraries/AllowFill.sol";
import { GenericSwapData, getGSDataHash } from "contracts/libraries/GenericSwapData.sol";
import { LimitOrder, getLimitOrderHash } from "contracts/libraries/LimitOrder.sol";
import { RFQOffer, getRFQOfferHash } from "contracts/libraries/RFQOffer.sol";
import { RFQTx, getRFQTxHash } from "contracts/libraries/RFQTx.sol";
import { Test } from "forge-std/Test.sol";

contract SigHelper is Test {
    function getEIP712Hash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        string memory EIP191_HEADER = "\x19\x01";
        return keccak256(abi.encodePacked(EIP191_HEADER, domainSeparator, structHash));
    }

    function computeEIP712DomainSeparator(address verifyingContract) internal view returns (bytes32) {
        bytes32 EIP712_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Tokenlon")),
                keccak256(bytes("v6")),
                block.chainid,
                verifyingContract
            )
        );
        return EIP712_DOMAIN_SEPARATOR;
    }

    function computeEIP712DomainSeparator(uint256 chainId, address verifyingContract) internal pure returns (bytes32) {
        bytes32 EIP712_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Tokenlon")),
                keccak256(bytes("v6")),
                chainId,
                verifyingContract
            )
        );
        return EIP712_DOMAIN_SEPARATOR;
    }

    function signAllowFill(uint256 _privateKey, AllowFill memory _allowFill, bytes32 domainSeperator) internal pure returns (bytes memory sig) {
        bytes32 allowFillHash = getAllowFillHash(_allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(domainSeperator, allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signAllowFill(uint256 _privateKey, AllowFill memory _allowFill, address verifyingContract) internal view returns (bytes memory sig) {
        bytes32 allowFillHash = getAllowFillHash(_allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(block.chainid, verifyingContract), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signAllowFill(
        uint256 _privateKey,
        AllowFill memory _allowFill,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes memory sig) {
        bytes32 allowFillHash = getAllowFillHash(_allowFill);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(chainId, verifyingContract), allowFillHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signGenericSwap(uint256 _privateKey, GenericSwapData memory _swapData, bytes32 domainSeperator) internal pure returns (bytes memory sig) {
        bytes32 swapHash = getGSDataHash(_swapData);
        bytes32 EIP712SignDigest = getEIP712Hash(domainSeperator, swapHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signGenericSwap(uint256 _privateKey, GenericSwapData memory _swapData, address verifyingContract) internal view returns (bytes memory sig) {
        bytes32 swapHash = getGSDataHash(_swapData);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(block.chainid, verifyingContract), swapHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signGenericSwap(
        uint256 _privateKey,
        GenericSwapData memory _swapData,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes memory sig) {
        bytes32 swapHash = getGSDataHash(_swapData);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(chainId, verifyingContract), swapHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signLimitOrder(uint256 _privateKey, LimitOrder memory _order, bytes32 domainSeperator) internal pure returns (bytes memory sig) {
        bytes32 orderHash = getLimitOrderHash(_order);
        bytes32 EIP712SignDigest = getEIP712Hash(domainSeperator, orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signLimitOrder(uint256 _privateKey, LimitOrder memory _order, address verifyingContract) internal view returns (bytes memory sig) {
        bytes32 orderHash = getLimitOrderHash(_order);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(block.chainid, verifyingContract), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signLimitOrder(
        uint256 _privateKey,
        LimitOrder memory _order,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes memory sig) {
        bytes32 orderHash = getLimitOrderHash(_order);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(chainId, verifyingContract), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signRFQOffer(uint256 _privateKey, RFQOffer memory _rfqOffer, bytes32 domainSeperator) internal pure returns (bytes memory sig) {
        bytes32 rfqOfferHash = getRFQOfferHash(_rfqOffer);
        bytes32 EIP712SignDigest = getEIP712Hash(domainSeperator, rfqOfferHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signRFQOffer(uint256 _privateKey, RFQOffer memory _rfqOffer, address verifyingContract) internal view returns (bytes memory sig) {
        bytes32 rfqOfferHash = getRFQOfferHash(_rfqOffer);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(block.chainid, verifyingContract), rfqOfferHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signRFQOffer(uint256 _privateKey, RFQOffer memory _rfqOffer, uint256 chainId, address verifyingContract) internal pure returns (bytes memory sig) {
        bytes32 rfqOfferHash = getRFQOfferHash(_rfqOffer);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(chainId, verifyingContract), rfqOfferHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signRFQTx(uint256 _privateKey, RFQTx memory _rfqTx, bytes32 domainSeperator) internal pure returns (bytes memory sig) {
        (, bytes32 rfqTxHash) = getRFQTxHash(_rfqTx);
        bytes32 EIP712SignDigest = getEIP712Hash(domainSeperator, rfqTxHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signRFQTx(uint256 _privateKey, RFQTx memory _rfqTx, address verifyingContract) internal view returns (bytes memory sig) {
        (, bytes32 rfqTxHash) = getRFQTxHash(_rfqTx);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(block.chainid, verifyingContract), rfqTxHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }

    function signRFQTx(uint256 _privateKey, RFQTx memory _rfqTx, uint256 chainId, address verifyingContract) internal pure returns (bytes memory sig) {
        (, bytes32 rfqTxHash) = getRFQTxHash(_rfqTx);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(chainId, verifyingContract), rfqTxHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, EIP712SignDigest);
        return abi.encodePacked(r, s, v);
    }
}
