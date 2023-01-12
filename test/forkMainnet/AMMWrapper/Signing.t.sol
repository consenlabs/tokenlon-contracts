// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "test/utils/StrategySharedSetup.sol";

function computeEIP712DomainSeparator(address verifyingContract) returns (bytes32) {
    uint256 CHAIN_ID = 1;
    bytes32 EIP712_DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("Tokenlon")),
            keccak256(bytes("v5")),
            CHAIN_ID,
            verifyingContract
        )
    );
    return EIP712_DOMAIN_SEPARATOR;
}

contract TestAMMWrapperSigning is StrategySharedSetup {
    function testAMMOrderEIP712Sig() public {
        string memory ammWrapperPayloadJson = vm.readFile("test/signing/payload/ammWrapper.json");

        AMMLibEIP712.Order memory order = AMMLibEIP712.Order(
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "makerAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "takerAssetAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "makerAssetAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "takerAssetAmount"), (uint256)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "makerAssetAmount"), (uint256)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "userAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "receiverAddr"), (address)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "salt"), (uint256)),
            abi.decode(vm.parseJson(ammWrapperPayloadJson, "deadline"), (uint256))
        );

        address ammWrapperAddr = abi.decode(vm.parseJson(ammWrapperPayloadJson, "AMMWrapper"), (address));
        uint256 userPrivateKey = abi.decode(vm.parseJson(ammWrapperPayloadJson, "signingKey"), (uint256));
        bytes memory sig = _signAMMTrade(ammWrapperAddr, userPrivateKey, order);

        bytes memory expectedSig = abi.decode(vm.parseJson(ammWrapperPayloadJson, "expectedSig"), (bytes));
        require(keccak256(sig) == keccak256(expectedSig), "Not expected AMM order sig");
    }

    function _signAMMTrade(
        address ammWrapperAddr,
        uint256 privateKey,
        AMMLibEIP712.Order memory order
    ) internal returns (bytes memory sig) {
        bytes32 orderHash = AMMLibEIP712._getOrderHash(order);
        bytes32 EIP712SignDigest = getEIP712Hash(computeEIP712DomainSeparator(ammWrapperAddr), orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }
}
