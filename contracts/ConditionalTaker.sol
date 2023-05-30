// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IConditionalTaker } from "./interfaces/IConditionalTaker.sol";
import { ILimitOrderSwap } from "./interfaces/ILimitOrderSwap.sol";
import { LimitOrder, getLimitOrderHash } from "./libraries/LimitOrder.sol";
import { AllowFill, getAllowFillHash } from "./libraries/AllowFill.sol";
import { Constant } from "./libraries/Constant.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

/// @title ConditionalTaker Contract
/// @author imToken Labs
contract ConditionalTaker is IConditionalTaker, Ownable, TokenCollector, EIP712 {
    using Asset for address;
    using SafeERC20 for IERC20;

    IWETH public immutable weth;
    ILimitOrderSwap public immutable limitOrderSwap;
    address public coordinator;

    mapping(bytes32 => bool) public allowFillUsed;

    constructor(
        address _owner,
        address _uniswapPermit2,
        address _allowanceTarget,
        IWETH _weth,
        address _coordinator,
        ILimitOrderSwap _limitOrderSwap
    ) Ownable(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {
        weth = _weth;
        coordinator = _coordinator;
        limitOrderSwap = _limitOrderSwap;
    }

    receive() external payable {}

    function setCoordinator(address _newCoordinator) external onlyOwner {
        if (_newCoordinator == address(0)) revert ZeroAddress();
        coordinator = _newCoordinator;

        emit SetCoordinator(_newCoordinator);
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

    function submitLimitOrderFill(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        uint256 takerTokenAmount,
        uint256 makerTokenAmount,
        bytes calldata extraAction,
        bytes calldata userTokenPermit,
        CoordinatorParams calldata crdParams
    ) external payable override {
        // validate fill permission
        {
            bytes32 orderHash = getLimitOrderHash(order);

            if (crdParams.expiry < uint64(block.timestamp)) revert ExpiredPermission();

            bytes32 allowFillHash = getEIP712Hash(
                getAllowFillHash(
                    AllowFill({ orderHash: orderHash, taker: msg.sender, fillAmount: makerTokenAmount, salt: crdParams.salt, expiry: crdParams.expiry })
                )
            );
            if (!SignatureValidator.isValidSignature(coordinator, allowFillHash, crdParams.sig)) revert InvalidSignature();

            if (allowFillUsed[allowFillHash]) revert ReusedPermission();
            allowFillUsed[allowFillHash] = true;
        }

        // collect taker token from user
        if (!order.takerToken.isETH()) {
            if (msg.value != 0) revert InvalidMsgValue();
            _collect(order.takerToken, msg.sender, address(this), takerTokenAmount, userTokenPermit);
        }

        // send order to limit order contract
        limitOrderSwap.fillLimitOrder{ value: msg.value }(
            order,
            makerSignature,
            ILimitOrderSwap.TakerParams({
                takerTokenAmount: takerTokenAmount,
                makerTokenAmount: makerTokenAmount,
                recipient: msg.sender,
                extraAction: extraAction,
                takerTokenPermit: abi.encode(TokenCollector.Source.Token, bytes(""))
            })
        );
    }
}
