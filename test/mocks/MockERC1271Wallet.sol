// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { IERC1271Wallet } from "contracts/interfaces/IERC1271Wallet.sol";

contract MockERC1271Wallet is IERC1271Wallet {
    using SafeERC20 for IERC20;

    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;
    uint256 private constant MAX_UINT = 2 ** 256 - 1;

    address public operator;

    modifier onlyOperator() {
        require(operator == msg.sender, "MockERC1271Wallet: not the operator");
        _;
    }

    constructor(address _operator) {
        operator = _operator;
    }

    receive() external payable {}

    function setAllowance(address[] memory _tokenList, address _spender) external onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, MAX_UINT);
        }
    }

    function closeAllowance(address[] memory _tokenList, address _spender) external onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, 0);
        }
    }

    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view override returns (bytes4 magicValue) {
        if (operator == ECDSA.recover(_hash, _signature)) {
            return ERC1271_MAGICVALUE;
        } else {
            return bytes4(0x12345678);
        }
    }
}
