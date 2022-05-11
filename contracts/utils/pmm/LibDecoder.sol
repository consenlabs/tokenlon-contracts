pragma solidity 0.7.6;
pragma abicoder v2;

import "../LibBytes.sol";
import "./LibOrder.sol";

contract LibDecoder {
    using LibBytes for bytes;

    function decodeFillOrder(bytes memory data)
        internal
        pure
        returns (
            LibOrder.Order memory order,
            uint256 takerFillAmount,
            bytes memory mmSignature
        )
    {
        require(data.length > 800, "LibDecoder: LENGTH_LESS_800");

        // compare method_id
        // 0x64a3bc15 is fillOrKillOrder's method id.
        require(data.readBytes4(0) == 0x64a3bc15, "LibDecoder: WRONG_METHOD_ID");

        bytes memory dataSlice;
        assembly {
            dataSlice := add(data, 4)
        }
        return abi.decode(dataSlice, (LibOrder.Order, uint256, bytes));
    }

    function decodeMmSignature(bytes memory signature)
        internal
        pure
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        v = uint8(signature[0]);
        r = signature.readBytes32(1);
        s = signature.readBytes32(33);

        return (v, r, s);
    }

    function decodeUserSignatureWithoutSign(bytes memory signature) internal pure returns (address receiver) {
        require(signature.length == 85 || signature.length == 86, "LibDecoder: LENGTH_85_REQUIRED");
        receiver = signature.readAddress(65);

        return receiver;
    }

    function decodeUserSignature(bytes memory signature)
        internal
        pure
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s,
            address receiver
        )
    {
        receiver = decodeUserSignatureWithoutSign(signature);

        v = uint8(signature[0]);
        r = signature.readBytes32(1);
        s = signature.readBytes32(33);

        return (v, r, s, receiver);
    }

    function decodeERC20Asset(bytes memory assetData) internal pure returns (address) {
        require(assetData.length == 36, "LibDecoder: LENGTH_36_REQUIRED");

        return assetData.readAddress(16);
    }
}
