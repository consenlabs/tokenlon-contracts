// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "contracts/utils/LibBytes.sol";
import "contracts/interfaces/ISetAllowance.sol";
import "contracts/interfaces/IERC1271Wallet.sol";

contract MockERC1271Wallet is ISetAllowance, IERC1271Wallet {
    using SafeERC20 for IERC20;
    using LibBytes for bytes;

    // bytes4(keccak256("isValidSignature(bytes,bytes)"))
    bytes4 internal constant ERC1271_MAGICVALUE = 0x20c13b0b;
    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 internal constant ERC1271_MAGICVALUE_BYTES32 = 0x1626ba7e;
    uint256 private constant MAX_UINT = 2**256 - 1;

    address public operator;

    modifier onlyOperator() {
        require(operator == msg.sender, "MockERC1271Wallet: not the operator");
        _;
    }

    constructor(address _operator) {
        operator = _operator;
    }

    function setAllowance(address[] memory _tokenList, address _spender) external override onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, MAX_UINT);
        }
    }

    function closeAllowance(address[] memory _tokenList, address _spender) external override onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, 0);
        }
    }

    function isValidSignature(bytes calldata _data, bytes calldata _signature) external view override returns (bytes4 magicValue) {
        require(operator == ECDSA.recover(keccak256(_data), _signature), "MockERC1271Wallet: invalid signature");
        return ERC1271_MAGICVALUE;
    }

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view override returns (bytes4 magicValue) {
        require(operator == ECDSA.recover(_hash, _signature), "MockERC1271Wallet: invalid signature");
        return ERC1271_MAGICVALUE_BYTES32;
    }
}
