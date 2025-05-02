// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "contracts/utils/AMMLibEIP712.sol";
import "test/utils/StrategySharedSetup.sol";
import { computeMainnetEIP712DomainSeparator, getEIP712Hash } from "test/utils/Sig.sol";

contract TestAMMWrapperSigning is StrategySharedSetup {
    function testAMMOrderEIP712Sig() public {
        string memory ammWrapperPayloadJson = vm.readFile("test/signing/payload/ammWrapper.json");

        AMMLibEIP712.Order memory order = AMMLibEIP712.Order(
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.makerAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.takerAssetAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.makerAssetAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.takerAssetAmount"), (uint256)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.makerAssetAmount"), (uint256)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.userAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.receiverAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.salt"), (uint256)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.deadline"), (uint256))
        );

        address ammWrapperAddr = abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.AMMWrapper"), (address));
        uint256 userPrivateKey = abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = _signAMMTrade(ammWrapperAddr, userPrivateKey, order);

        bytes memory expectedSig = abi.decode(vm.parseJson(ammWrapperPayloadJson, "$.expectedSig"), (bytes));
        require(keccak256(sig) == keccak256(expectedSig), "Not expected AMM order sig");
    }

    function _signAMMTrade(address ammWrapperAddr, uint256 privateKey, AMMLibEIP712.Order memory order) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(ammWrapperAddr), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }
}
