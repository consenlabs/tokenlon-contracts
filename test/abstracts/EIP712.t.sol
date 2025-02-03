// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { EIP712 } from "contracts/abstracts/EIP712.sol";

contract EIP712Test is Test {
    EIP712Harness eip712Harness;

    // Dummy struct hash for testing
    bytes32 public constant DUMMY_STRUCT_HASH = keccak256("DummyStruct(string message)");

    function setUp() public {
        eip712Harness = new EIP712Harness();
    }

    function testOriginalChainId() public {
        uint256 chainId = block.chainid;
        assertEq(eip712Harness.originalChainId(), chainId);
    }

    function testOriginalDomainSeparator() public {
        bytes32 expectedDomainSeparator = eip712Harness.calculateDomainSeparator();
        assertEq(eip712Harness.originalEIP712DomainSeparator(), expectedDomainSeparator);
    }

    function testGetEIP712Hash() public {
        bytes32 structHash = DUMMY_STRUCT_HASH;
        bytes32 domainSeparator = eip712Harness.calculateDomainSeparator();
        bytes32 expectedEIP712Hash = keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));

        assertEq(eip712Harness.exposedGetEIP712Hash(structHash), expectedEIP712Hash);
        vm.snapshotGasLastCall("EIP712", "getEIP712Hash(): testGetEIP712Hash");
    }

    function testDomainSeparatorOnDifferentChain() public {
        uint256 chainId = block.chainid + 1234;
        vm.chainId(chainId);

        bytes32 newDomainSeparator = eip712Harness.calculateDomainSeparator();
        assertEq(eip712Harness.EIP712_DOMAIN_SEPARATOR(), newDomainSeparator, "Domain separator should match the expected value on a different chain");
        vm.snapshotGasLastCall("EIP712", "EIP712_DOMAIN_SEPARATOR(): testDomainSeparatorOnDifferentChain");
    }

    function testDomainSeparatorOnChain() public {
        eip712Harness.EIP712_DOMAIN_SEPARATOR();
        vm.snapshotGasLastCall("EIP712", "EIP712_DOMAIN_SEPARATOR(): testDomainSeparatorOnChain");
    }
}

contract EIP712Harness is EIP712 {
    function calculateDomainSeparator() external view returns (bytes32) {
        return keccak256(abi.encode(EIP712_TYPE_HASH, keccak256(bytes(EIP712_NAME)), keccak256(bytes(EIP712_VERSION)), block.chainid, address(this)));
    }

    function exposedGetEIP712Hash(bytes32 structHash) public view returns (bytes32) {
        return getEIP712Hash(structHash);
    }
}
