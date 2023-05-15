// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ownable } from "./abstracts/Ownable.sol";
import { Asset } from "./libraries/Asset.sol";
import { Constant } from "./libraries/Constant.sol";
import { IWETH } from "./interfaces/IWeth.sol";
import { IUniswapPermit2 } from "./interfaces/IUniswapPermit2.sol";
import { ISmartOrderStrategy } from "./interfaces/ISmartOrderStrategy.sol";
import { IStrategy } from "./interfaces/IStrategy.sol";

contract SmartOrderStrategy is ISmartOrderStrategy, Ownable {
    using SafeERC20 for IERC20;

    address public immutable weth;
    address public immutable permit2;
    address public immutable entryPoint;

    receive() external payable {}

    constructor(
        address _owner,
        address _entryPoint,
        address _weth,
        address _permit2
    ) Ownable(_owner) {
        entryPoint = _entryPoint;
        weth = _weth;
        permit2 = _permit2;
    }

    modifier onlyEntryPoint() {
        require(msg.sender == entryPoint, "only entry point");
        _;
    }

    /// @inheritdoc ISmartOrderStrategy
    function approveTokens(
        address[] calldata tokens,
        address[] calldata spenders,
        bool[] calldata usePermit2InSpenders,
        uint256 amount
    ) external override onlyOwner {
        require(spenders.length == usePermit2InSpenders.length, "length of spenders not match");
        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                if (usePermit2InSpenders[j]) {
                    // The UniversalRouter of Uniswap uses Permit2 to remove the need for token approvals being provided directly to the UniversalRouter.
                    _permit2Approve(tokens[i], spenders[j], amount);
                } else {
                    IERC20(tokens[i]).safeApprove(spenders[j], amount);
                }
            }
        }
    }

    /// @inheritdoc ISmartOrderStrategy
    function withdrawLegacyTokensTo(address[] calldata tokens, address receiver) external override onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 selfBalance = Asset.getBalance(tokens[i], address(this));
            if (selfBalance > 0) {
                Asset.transferTo(tokens[i], payable(receiver), selfBalance);
            }
        }
    }

    /// @inheritdoc IStrategy
    function executeStrategy(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        bytes calldata data
    ) external payable override onlyEntryPoint {
        if (inputAmount == 0) revert EmptyInput();

        Operation[] memory ops = abi.decode(data, (Operation[]));
        if (ops.length == 0) revert EmptyOps();

        // wrap eth first
        if (Asset.isETH(inputToken)) {
            if (msg.value != inputAmount) revert InvalidMsgValue();
            IWETH(weth).deposit{ value: inputAmount }();
        }

        for (uint256 i = 0; i < ops.length; ++i) {
            Operation memory op = ops[i];
            bytes4 selector = _call(op.dest, op.inputToken, op.inputRatio, op.dataOffset, op.value, op.data);
            emit Action(op.dest, op.value, selector);
        }
        _transferToEntryPoint(outputToken);
    }

    /**
     * @dev internal function of `executeStrategy`.
     * Allow arbitrary call to allowed amms in swap
     */
    function _call(
        address _dest,
        address _inputToken,
        uint128 _inputRatio,
        uint128 _dataOffset,
        uint256 _value,
        bytes memory _data
    ) internal returns (bytes4 selector) {
        selector = bytes4(_data);

        uint256 tokenInput = IERC20(_inputToken).balanceOf(address(this));

        // calculate input amount if ratio should be applied
        if (_inputRatio != Constant.BPS_MAX) {
            tokenInput = (IERC20(_inputToken).balanceOf(address(this)) * _inputRatio) / Constant.BPS_MAX;
        }
        assembly {
            mstore(add(_data, _dataOffset), tokenInput)
        }

        (bool success, bytes memory result) = _dest.call{ value: _value }(_data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @dev internal function of `executeStrategy`.
     * Allow the spender to use Permit2 for the token.
     */
    function _permit2Approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), permit2) == 0) {
            IERC20(_token).safeApprove(permit2, type(uint256).max);
        }
        uint160 amount = _amount > type(uint160).max ? type(uint160).max : uint160(_amount);
        IUniswapPermit2(permit2).approve(_token, _spender, amount, type(uint48).max);
    }

    /**
     * @dev internal function of `executeStrategy`.
     * Transfer output token to entry point
     * If outputToken is native ETH and there is WETH remain, unwrap WETH to ETH automatically
     */
    function _transferToEntryPoint(address _token) internal {
        if (Asset.isETH(_token)) {
            // unwrap existing WETH
            uint256 wethBalance = IWETH(weth).balanceOf(address(this));
            if (wethBalance > 0) {
                IWETH(weth).withdraw(wethBalance);
            }
        }
        uint256 selfBalance = Asset.getBalance(_token, address(this));
        if (selfBalance > 0) {
            Asset.transferTo(_token, payable(entryPoint), selfBalance);
        }
    }
}
