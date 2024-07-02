// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { EIP712 } from "contracts/abstracts/EIP712.sol";

contract EIP712Test is Test {
    EIP712TestContract eip712;

    // Dummy struct hash for testing
    bytes32 public constant DUMMY_STRUCT_HASH = keccak256("DummyStruct(string message)");

    function setUp() public {
        eip712 = new EIP712TestContract();
    }

    function testOriginalChainId() public {
        uint256 chainId = block.chainid;
        assertEq(eip712.originalChainId(), chainId);
    }

    function testOriginalDomainSeparator() public {
        bytes32 expectedDomainSeparator = eip712.calculateDomainSeparator();
        assertEq(eip712.originalEIP712DomainSeparator(), expectedDomainSeparator);
    }

    function testGetEIP712Hash() public {
        bytes32 structHash = DUMMY_STRUCT_HASH;
        bytes32 domainSeparator = eip712.calculateDomainSeparator();
        bytes32 expectedEIP712Hash = keccak256(abi.encodePacked(eip712.EIP191_HEADER(), domainSeparator, structHash));

        assertEq(eip712.getEIP712HashWrap(structHash), expectedEIP712Hash);
    }

    function testDomainSeparatorOnDifferentChain() public {
        uint256 chainId = block.chainid + 1234;
        vm.chainId(chainId);

        bytes32 newDomainSeparator = eip712.calculateDomainSeparator();
        assertEq(eip712.EIP712_DOMAIN_SEPARATOR(), newDomainSeparator, "Domain separator should match the expected value on a different chain");
    }
}

contract EIP712TestContract is EIP712 {
    function calculateDomainSeparator() external view returns (bytes32) {
        return keccak256(abi.encode(EIP712_TYPE_HASH, keccak256(bytes(EIP712_NAME)), keccak256(bytes(EIP712_VERSION)), block.chainid, address(this)));
    }

    function getEIP712HashWrap(bytes32 structHash) public view returns (bytes32) {
        return super.getEIP712Hash(structHash);
    }
}
