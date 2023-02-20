// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
// interface, abstract, contract 0.8.17
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IStrategy.sol";
import "./interfaces/IUniswapRouterV2.sol";

contract AMMStrategy is IStrategy, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct Operation {
        address dest;
        bytes data;
    }

    /// @notice Emitted when entry point address is updated
    /// @param newEntryPoint The address of the new entry point
    event SetEntryPoint(address newEntryPoint);

    /// @notice Emitted after swap with AMM
    /// @param takerAssetAddr The taker assest used to swap
    /// @param takerAssetAmount The swap amount of taker asset
    /// @param makerAddr The address of maker
    /// @param makerAssetAddr The maker assest used to swap
    /// @param makerAssetAmount The swap amount of maker asset
    event Swapped(address takerAssetAddr, uint256 takerAssetAmount, address[] makerAddr, address makerAssetAddr, uint256 makerAssetAmount);

    address public entryPoint;
    mapping(address => bool) public ammMapping;

    constructor(address _entryPoint, address[] memory amms) {
        entryPoint = _entryPoint;
        for (uint256 i = 0; i < amms.length; ++i) {
            ammMapping[amms[i]] = true;
            // should emit
        }
    }

    modifier onlyEntryPoint() {
        require(msg.sender == entryPoint, "only entry point");
        _;
    }

    function approveTakerAsset(
        address takerAssetAddr,
        address makerAddr,
        uint256 takerAssetAmount
    ) external onlyOwner {
        IERC20(takerAssetAddr).safeApprove(makerAddr, takerAssetAmount);
    }

    function approveAMMs(address[] calldata amms, bool[] calldata enables) external onlyOwner {
        for (uint256 i = 0; i < amms.length; ++i) {
            ammMapping[amms[i]] = enables[i];
            // should emit
        }
    }

    function setEntryPoint(address _newEntryPoint) external onlyOwner {
        entryPoint = _newEntryPoint;
        emit SetEntryPoint(_newEntryPoint);
    }

    // only work for erc-20
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
        emit Swapped(srcToken, inputAmount, opDests, targetToken, balanceAfter - balanceBefore);
    }

    function _call(
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, bytes memory result) = target.call{ value: value }(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
