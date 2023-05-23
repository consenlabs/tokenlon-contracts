// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

abstract contract BaseLibEIP712 {
    // EIP-191 Header
    string public constant EIP191_HEADER = "\x19\x01";

    // EIP712Domain
    string public constant EIP712_DOMAIN_NAME = "Tokenlon";
    string public constant EIP712_DOMAIN_VERSION = "v5";

    // EIP712Domain Separator
    bytes32 public immutable originalEIP712DomainSeparator;
    uint256 public immutable originalChainId;

    constructor() {
        originalEIP712DomainSeparator = _buildDomainSeparator();
        originalChainId = getChainID();
    }

    /**
     * @dev Return `chainId`
     */
    function getChainID() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(EIP712_DOMAIN_NAME)),
                    keccak256(bytes(EIP712_DOMAIN_VERSION)),
                    getChainID(),
                    address(this)
                )
            );
    }

    function _getDomainSeparator() private view returns (bytes32) {
        if (getChainID() == originalChainId) {
            return originalEIP712DomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function getEIP712Hash(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(EIP191_HEADER, _getDomainSeparator(), structHash));
    }

    function EIP712_DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _getDomainSeparator();
    }
}
