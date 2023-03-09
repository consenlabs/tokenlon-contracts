// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { Asset } from "./libraries/Asset.sol";
import { IAMMStrategy } from "./interfaces/IAMMStrategy.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";

contract AMMStrategy is IAMMStrategy, Ownable {
    using SafeERC20 for IERC20;

    address public entryPoint;
    mapping(address => bool) public ammMapping;

    receive() external payable {}

    /************************************************************
     *              Constructor and init functions               *
     *************************************************************/

    constructor(
        address _owner,
        address _entryPoint,
        address[] memory _ammAddrs
    ) Ownable(_owner) {
        entryPoint = _entryPoint;
        for (uint256 i = 0; i < _ammAddrs.length; ++i) {
            ammMapping[_ammAddrs[i]] = true;
            emit SetAMM(_ammAddrs[i], true);
        }
    }

    /************************************************************
     *                 Internal function modifier                *
     *************************************************************/
    modifier onlyEntryPoint() {
        require(msg.sender == entryPoint, "only entry point");
        _;
    }

    /************************************************************
     *           Management functions for Owner               *
     *************************************************************/
    /// @inheritdoc IAMMStrategy
    function setAMMs(address[] calldata _ammAddrs, bool[] calldata _enables) external override onlyOwner {
        for (uint256 i = 0; i < _ammAddrs.length; ++i) {
            ammMapping[_ammAddrs[i]] = _enables[i];
            emit SetAMM(_ammAddrs[i], true);
        }
    }

    /// @inheritdoc IAMMStrategy
    function approveTokens(
        address[] calldata tokens,
        address[] calldata spenders,
        uint256 amount
    ) external override onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                IERC20(tokens[i]).safeApprove(spenders[j], amount);
            }
        }
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    /// @inheritdoc IStrategy
    function executeStrategy(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        bytes calldata data
    ) external payable override onlyEntryPoint {
        Operation[] memory ops = abi.decode(data, (Operation[]));
        require(ops.length > 0, "empty operations");
        require(inputAmount > 0, "empty inputAmount");
        uint256 balanceBefore = Asset.getBalance(outputToken, entryPoint);
        for (uint256 i = 0; i < ops.length; ++i) {
            Operation memory op = ops[i];
            require(ammMapping[op.dest], "invalid op dest");
            _call(op.dest, 0, op.data);
        }
        uint256 selfBalance = Asset.getBalance(outputToken, address(this));
        if (selfBalance > 0) {
            Asset.transferTo(outputToken, payable(entryPoint), selfBalance);
        }
        uint256 balanceAfter = Asset.getBalance(outputToken, entryPoint);
        emit Swapped(inputToken, inputAmount, outputToken, balanceAfter - balanceBefore);
    }

    /**
     * @dev internal function of `executeStrategy`.
     * Used to execute arbitrary calls.
     */
    function _call(
        address _dest,
        uint256 _value,
        bytes memory _data
    ) internal {
        (bool success, bytes memory result) = _dest.call{ value: _value }(_data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
