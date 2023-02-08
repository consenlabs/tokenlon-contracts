// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "contracts/utils/L2DepositLibEIP712.sol";
import "test/utils/StrategySharedSetup.sol";
import { computeMainnetEIP712DomainSeparator, getEIP712Hash } from "test/utils/Sig.sol";

contract TestL2DepositWrapperSigning is StrategySharedSetup {
    function testL2DepositEIP712Sig() public {
        string memory l2DepositPayloadJson = vm.readFile("test/signing/payload/l2Deposit.json");

        L2DepositLibEIP712.Deposit memory deposit = L2DepositLibEIP712.Deposit(
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.l2Identifier"), (L2DepositLibEIP712.L2Identifier)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.l1TokenAddr"), (address)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.l2TokenAddr"), (address)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.sender"), (address)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.recipient"), (address)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.amount"), (uint256)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.salt"), (uint256)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.expiry"), (uint256)),
            abi.decode(vm.parseJson(l2DepositPayloadJson, "$.data"), (bytes))
        );

        address l2DepositAddr = abi.decode(vm.parseJson(l2DepositPayloadJson, "$.L2Deposit"), (address));
        uint256 signingKey = abi.decode(vm.parseJson(l2DepositPayloadJson, "$.signingKey"), (uint256));
        bytes memory sig = _signL2Deposit(l2DepositAddr, signingKey, deposit);

        bytes memory expectedSig = abi.decode(vm.parseJson(l2DepositPayloadJson, "$.expectedSig"), (bytes));
        require(keccak256(sig) == keccak256(expectedSig), "Not expected L2Deposit sig");
    }

    function _signL2Deposit(
        address l2DepositAddr,
        uint256 privateKey,
        L2DepositLibEIP712.Deposit memory deposit
    ) internal returns (bytes memory sig) {
        bytes32 depositHash = L2DepositLibEIP712._getDepositHash(deposit);
        bytes32 EIP712SignDigest = getEIP712Hash(computeMainnetEIP712DomainSeparator(l2DepositAddr), depositHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, EIP712SignDigest);
        sig = abi.encodePacked(r, s, v, bytes32(0), uint8(2));
    }
}
