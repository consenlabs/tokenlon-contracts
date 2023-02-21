// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
// interface, abstract, contract 0.8.17
pragma abicoder v2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IAMMStrategy.sol";
import "./interfaces/IUniswapRouterV2.sol";

contract AMMStrategy is IAMMStrategy, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public entryPoint;
    mapping(address => bool) public ammMapping;

    /************************************************************
     *              Constructor and init functions               *
     *************************************************************/

    constructor(address _entryPoint, address[] memory _ammAddrs) {
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
    /// @notice Only owner can call
    /// @param _newEntryPoint The address allowed to call `executeStrategy`
    function setEntryPoint(address _newEntryPoint) external onlyOwner {
        entryPoint = _newEntryPoint;
        emit SetEntryPoint(_newEntryPoint);
    }

    /// @notice Only owner can call
    /// @param _ammAddrs The amm addresses allowed to use in `executeStrategy` if according `enable` equals `true`
    /// @param _enables The status of accouring amm addresses
    function setAMMs(address[] calldata _ammAddrs, bool[] calldata _enables) external onlyOwner {
        for (uint256 i = 0; i < _ammAddrs.length; ++i) {
            ammMapping[_ammAddrs[i]] = _enables[i];
            emit SetAMM(_ammAddrs[i], true);
        }
    }

    /// @notice Only owner can call
    /// @param _assetAddrs The asset addresses
    /// @param _ammAddrs The approved amm addresses
    /// @param _assetAmounts The approved asset amounts
    function approveAssets(
        address[] _assetAddrs,
        address[][] _ammAddrs,
        uint256[] _assetAmounts
    ) external onlyOwner {
        for (uint256 i = 0; i < _assetAddrs.length; ++i) {
            for (uint256 j = 0; j < _ammAddrs[i].length; ++j) {
                IERC20(_assetAddrs[i]).safeApprove(_ammAddrs[i][j], _assetAmounts[i]);
            }
        }
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    /// @inheritdoc IStrategy
    function executeStrategy(
        address srcToken,
        uint256 inputAmount,
        address targetToken,
        bytes calldata data
    ) external override nonReentrant onlyEntryPoint {
        Operation[] memory ops = abi.decode(data, (Operation[]));
        require(ops.length > 0, "empty operations");
        uint256 balanceBefore = IERC20(targetToken).balanceOf(entryPoint);
        address[] memory opDests = new address[](ops.length);
        for (uint256 i = 0; i < ops.length; ++i) {
            Operation memory op = ops[i];
            require(ammMapping[op.dest], "not a valid operation destination");
            opDests[i] = op.dest;
            _call(op.dest, 0, op.data);
        }
        uint256 receivedAmount = IERC20(targetToken).balanceOf(address(this));
        if (receivedAmount != 0) {
            IERC20(targetToken).safeTransfer(entryPoint, receivedAmount);
        }
        uint256 balanceAfter = IERC20(targetToken).balanceOf(entryPoint);
        emit Swapped(srcToken, inputAmount, opDests, targetToken, balanceAfter.sub(balanceBefore));
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
