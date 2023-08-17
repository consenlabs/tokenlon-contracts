// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { IUniAgent } from "./interfaces/IUniAgent.sol";
import { Asset } from "./libraries/Asset.sol";

contract UniAgent is IUniAgent, Ownable, TokenCollector {
    using Asset for address;

    address private constant v2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant v3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant swapRouter02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address payable private constant universalRouter = payable(0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD);

    constructor(
        address _owner,
        address _uniswapPermit2,
        address _allowanceTarget
    ) Ownable(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {}

    receive() external payable {}

    function rescueTokens(address[] calldata tokens, address recipient) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 selfBalance = Asset.getBalance(tokens[i], address(this));
            if (selfBalance > 0) {
                Asset.transferTo(tokens[i], payable(recipient), selfBalance);
            }
        }
    }

    function approveTokensToRouters(address[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; ++i) {
            // use low level call to avoid return size check
            // ignore return value and proceed anyway since three calls are independent
            tokens[i].call(abi.encodeCall(IERC20.approve, (v2Router, type(uint256).max)));
            tokens[i].call(abi.encodeCall(IERC20.approve, (v3Router, type(uint256).max)));
            tokens[i].call(abi.encodeCall(IERC20.approve, (swapRouter02, type(uint256).max)));
        }
    }

    /// @inheritdoc IUniAgent
    function approveAndSwap(
        RouterType routerType,
        address inputToken,
        uint256 inputAmount,
        bytes calldata payload,
        bytes calldata userPermit
    ) external payable override {
        _swap(routerType, true, inputToken, inputAmount, payload, userPermit);
    }

    /// @inheritdoc IUniAgent
    function swap(
        RouterType routerType,
        address inputToken,
        uint256 inputAmount,
        bytes calldata payload,
        bytes calldata userPermit
    ) external payable override {
        _swap(routerType, false, inputToken, inputAmount, payload, userPermit);
    }

    function _swap(
        RouterType routerType,
        bool needApprove,
        address inputToken,
        uint256 inputAmount,
        bytes calldata payload,
        bytes calldata userPermit
    ) private {
        address routerAddr = _getRouterAddress(routerType);
        if (needApprove) {
            // use low level call to avoid return size check
            (bool apvSuccess, bytes memory apvResult) = inputToken.call(abi.encodeCall(IERC20.approve, (routerAddr, type(uint256).max)));
            if (!apvSuccess) {
                assembly {
                    revert(add(apvResult, 32), mload(apvResult))
                }
            }
        }

        if (inputToken.isETH()) {
            if (msg.value != inputAmount) revert InvalidMsgValue();
        }
        if (!inputToken.isETH()) {
            if (msg.value != 0) revert InvalidMsgValue();

            if (routerType == RouterType.UniversalRouter) {
                // deposit directly into router if it's universal router
                _collect(inputToken, msg.sender, universalRouter, inputAmount, userPermit);
            } else {
                // v2, v3, swapRouter02 use transferFrom
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
        } else if (routerType == RouterType.SwapRouter02) {
            return swapRouter02;
        } else if (routerType == RouterType.UniversalRouter) {
            return universalRouter;
        }

        // won't be reached
        revert();
    }
}
