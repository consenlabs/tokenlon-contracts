// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "./abstracts/Ownable.sol";
import { Asset } from "./libraries/Asset.sol";
import { Constant } from "./libraries/Constant.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IUniswapPermit2 } from "./interfaces/IUniswapPermit2.sol";
import { ISmartOrderStrategy } from "./interfaces/ISmartOrderStrategy.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";

contract SmartOrderStrategy is ISmartOrderStrategy, Ownable {
    using SafeERC20 for IERC20;

    address public immutable weth;
    address public immutable genericSwap;

    receive() external payable {}

    constructor(
        address _owner,
        address _genericSwap,
        address _weth
    ) Ownable(_owner) {
        genericSwap = _genericSwap;
        weth = _weth;
    }

    modifier onlyGenericSwap() {
        if (msg.sender != genericSwap) revert NotFromGS();
        _;
    }

    /// @inheritdoc ISmartOrderStrategy
    function approveTokens(address[] calldata tokens, address[] calldata spenders) external override onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                IERC20(tokens[i]).safeApprove(spenders[j], Constant.MAX_UINT);
            }
        }
    }

    /// @inheritdoc ISmartOrderStrategy
    function withdrawTokens(address[] calldata tokens, address recipient) external override onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 selfBalance = Asset.getBalance(tokens[i], address(this));
            if (selfBalance > 0) {
                Asset.transferTo(tokens[i], payable(recipient), selfBalance);
            }
        }
    }

    /// @inheritdoc IStrategy
    function executeStrategy(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        bytes calldata data
    ) external payable override onlyGenericSwap {
        if (inputAmount == 0) revert ZeroInput();

        Operation[] memory ops = abi.decode(data, (Operation[]));
        if (ops.length == 0) revert EmptyOps();

        // wrap eth first
        if (Asset.isETH(inputToken)) {
            if (msg.value != inputAmount) revert InvalidMsgValue();
            IWETH(weth).deposit{ value: inputAmount }();
        } else {
            if (msg.value != 0) revert InvalidMsgValue();
        }

        for (uint256 i = 0; i < ops.length; ++i) {
            Operation memory op = ops[i];
            _call(op.dest, op.inputToken, op.inputRatio, op.dataOffset, op.value, op.data);
        }

        // transfer output token back to GenericSwap
        // ETH first so WETH is not considered as an option of outputToken
        if (Asset.isETH(outputToken)) {
            // unwrap existing WETH if any
            uint256 wethBalance = IWETH(weth).balanceOf(address(this));
            if (wethBalance > 0) {
                IWETH(weth).withdraw(wethBalance);
            }
        }
        uint256 selfBalance = Asset.getBalance(outputToken, address(this));
        Asset.transferTo(outputToken, payable(genericSwap), selfBalance);
    }

    function _call(
        address _dest,
        address _inputToken,
        uint128 _inputRatio,
        uint128 _dataOffset,
        uint256 _value,
        bytes memory _data
    ) internal {
        require(_inputRatio <= Constant.BPS_MAX, "invalid BPS");

        // replace amount if ratio != 0
        if (_inputRatio != 0) {
            uint256 inputTokenBalance = IERC20(_inputToken).balanceOf(address(this));

            // calculate input amount if ratio should be applied
            if (_inputRatio != Constant.BPS_MAX) {
                inputTokenBalance = (inputTokenBalance * _inputRatio) / Constant.BPS_MAX;
            }
            assembly {
                mstore(add(_data, _dataOffset), inputTokenBalance)
            }
        }

        (bool success, bytes memory result) = _dest.call{ value: _value }(_data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
