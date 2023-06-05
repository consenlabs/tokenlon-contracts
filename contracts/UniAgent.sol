// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IUniAgent } from "./interfaces/IUniAgent.sol";
import { Asset } from "./libraries/Asset.sol";
import { Constant } from "./libraries/Constant.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract UniAgent is Ownable, IUniAgent, TokenCollector, EIP712 {
    using Asset for address;
    using SafeERC20 for IERC20;

    address private constant v2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant v3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address payable private constant universalRouter = payable(0xEf1c6E67703c7BD7107eed8303Fbe6EC2554BF6B);

    IWETH public immutable weth;
    address payable public feeCollector;

    mapping(bytes32 => bool) private filledOrder;

    /// @notice Emitted when fee collector address is updated
    /// @param newFeeCollector The address of the new fee collector
    event SetFeeCollector(address newFeeCollector);

    constructor(
        address _owner,
        address _uniswapPermit2,
        address _allowanceTarget,
        IWETH _weth,
        address payable _feeCollector
    ) Ownable(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {
        weth = _weth;
        feeCollector = _feeCollector;
    }

    receive() external payable {}

    function setFeeCollector(address payable _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert ZeroAddress();
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    function approveTokens(address[] calldata tokens, address[] calldata spenders) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            for (uint256 j = 0; j < spenders.length; ++j) {
                IERC20(tokens[i]).safeApprove(spenders[j], Constant.MAX_UINT);
            }
        }
    }

    function withdrawTokens(address[] calldata tokens, address recipient) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 selfBalance = Asset.getBalance(tokens[i], address(this));
            if (selfBalance > 0) {
                Asset.transferTo(tokens[i], payable(recipient), selfBalance);
            }
        }
    }

    function swap(
        RouterType routerType,
        address inputToken,
        uint256 inputAmount,
        bytes calldata payload,
        bytes calldata userPermit
    ) external payable override {
        address routerAddr = _getRouterAddress(routerType);

        if (inputToken.isETH() && msg.value != inputAmount) revert InvalidMsgValue();
        if (!inputToken.isETH()) {
            if (msg.value != 0) revert InvalidMsgValue();

            if (routerType == RouterType.UniversalRouter) {
                // deposit directly into router if it's universal router
                _collect(inputToken, msg.sender, universalRouter, inputAmount, userPermit);
            } else {
                // v2 v3 use transferFrom
                _collect(inputToken, msg.sender, address(this), inputAmount, userPermit);
            }
        }
        (bool success, bytes memory result) = routerAddr.call{ value: msg.value }(payload);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit Swap({ user: msg.sender, router: routerAddr, inputToken: inputToken, inputAmount: inputAmount });
    }

    function _getRouterAddress(RouterType routerType) private pure returns (address) {
        if (routerType == RouterType.V2Router) {
            return v2Router;
        } else if (routerType == RouterType.V3Router) {
            return v3Router;
        } else if (routerType == RouterType.UniversalRouter) {
            return universalRouter;
        } else {
            revert UnknownRouterType();
        }
    }
}
