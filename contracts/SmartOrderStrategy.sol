// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AdminManagement } from "./abstracts/AdminManagement.sol";
import { Asset } from "./libraries/Asset.sol";
import { Constant } from "./libraries/Constant.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { ISmartOrderStrategy } from "./interfaces/ISmartOrderStrategy.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";

contract SmartOrderStrategy is ISmartOrderStrategy, AdminManagement {
    address public immutable weth;
    address public immutable genericSwap;

    receive() external payable {}

    constructor(address _owner, address _genericSwap, address _weth) AdminManagement(_owner) {
        genericSwap = _genericSwap;
        weth = _weth;
    }

    modifier onlyGenericSwap() {
        if (msg.sender != genericSwap) revert NotFromGS();
        _;
    }

    /// @inheritdoc IStrategy
    function executeStrategy(address inputToken, address outputToken, uint256 inputAmount, bytes calldata data) external payable override onlyGenericSwap {
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

        uint256 opsCount = ops.length;
        for (uint256 i = 0; i < opsCount; ++i) {
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
        if (selfBalance > 1) {
            unchecked {
                --selfBalance;
            }
        }
        Asset.transferTo(outputToken, payable(genericSwap), selfBalance);
    }

    function _call(address _dest, address _inputToken, uint128 _inputRatio, uint128 _dataOffset, uint256 _value, bytes memory _data) internal {
        if (_inputRatio > Constant.BPS_MAX) revert InvalidInputRatio();

        // replace amount if ratio != 0
        if (_inputRatio != 0) {
            uint256 inputTokenBalance = IERC20(_inputToken).balanceOf(address(this));
            // leaving one wei for gas optimization
            if (inputTokenBalance > 1) {
                unchecked {
                    --inputTokenBalance;
                }
            }

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
