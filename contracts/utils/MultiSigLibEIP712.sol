pragma solidity 0.6.12;

contract MultiSigLibEIP712 {
    /***********************************|
  |             Constants             |
  |__________________________________*/

    // EIP712Domain
    string public constant EIP712_DOMAIN_NAME = "MultiSig";
    string public constant EIP712_DOMAIN_VERSION = "v1";

    // EIP712Domain Separator
    bytes32 public EIP712_DOMAIN_SEPARATOR;

    // SUBMIT_TRANSACTION_TYPE_HASH = keccak256("submitTransaction(uint256 transactionId,address destination,uint256 value,bytes data)");
    bytes32 public constant SUBMIT_TRANSACTION_TYPE_HASH = 0x2c78e27c3bb2592e67e8d37ad1a95bfccd188e77557c22593b1af0b920a08295;

    // CONFIRM_TRANSACTION_TYPE_HASH = keccak256("confirmTransaction(uint256 transactionId)");
    bytes32 public constant CONFIRM_TRANSACTION_TYPE_HASH = 0x3e96bdc38d4133bc81813a187b2d41bc74332643ce7dbe82c7d94ead8366a65f;

    constructor() public {
        EIP712_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(EIP712_DOMAIN_NAME)),
                keccak256(bytes(EIP712_DOMAIN_VERSION)),
                getChainID(),
                address(this)
            )
        );
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
}
