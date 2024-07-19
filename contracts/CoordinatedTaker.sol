// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { AdminManagement } from "./abstracts/AdminManagement.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { ICoordinatedTaker } from "./interfaces/ICoordinatedTaker.sol";
import { ILimitOrderSwap } from "./interfaces/ILimitOrderSwap.sol";
import { LimitOrder, getLimitOrderHash } from "./libraries/LimitOrder.sol";
import { AllowFill, getAllowFillHash } from "./libraries/AllowFill.sol";
import { Asset } from "./libraries/Asset.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

/// @title CoordinatedTaker Contract
/// @author imToken Labs
/// @notice This contract is a taker contract for the LimitOrderSwap.
/// @dev It helps users avoid collisions when filling a limit order and provides an off-chain order canceling mechanism.
/// For more details, check the reference: https://github.com/consenlabs/tokenlon-contracts/blob/v6.0.1/doc/CoordinatedTaker.md
contract CoordinatedTaker is ICoordinatedTaker, AdminManagement, TokenCollector, EIP712 {
    using Asset for address;

    IWETH public immutable weth;
    ILimitOrderSwap public immutable limitOrderSwap;
    address public coordinator;

    /// @notice Mapping to keep track of used allow fill hashes.
    mapping(bytes32 allowFillHash => bool isUsed) public allowFillUsed;

    /// @notice Constructor to initialize the contract with the owner, Uniswap permit2, allowance target, WETH, coordinator and LimitOrderSwap contract.
    /// @param _owner The address of the contract owner.
    /// @param _uniswapPermit2 The address for Uniswap permit2.
    /// @param _allowanceTarget The address for the allowance target.
    /// @param _weth The WETH contract instance.
    /// @param _coordinator The initial coordinator address.
    /// @param _limitOrderSwap The LimitOrderSwap contract address.
    constructor(
        address _owner,
        address _uniswapPermit2,
        address _allowanceTarget,
        IWETH _weth,
        address _coordinator,
        ILimitOrderSwap _limitOrderSwap
    ) AdminManagement(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {
        weth = _weth;
        coordinator = _coordinator;
        limitOrderSwap = _limitOrderSwap;
    }

    /// @notice Receive function to receive ETH.
    receive() external payable {}

    /// @notice Sets a new coordinator address.
    /// @dev Only the owner can call this function.
    /// @param _newCoordinator The address of the new coordinator.
    function setCoordinator(address _newCoordinator) external onlyOwner {
        if (_newCoordinator == address(0)) revert ZeroAddress();
        coordinator = _newCoordinator;

        emit SetCoordinator(_newCoordinator);
    }

    /// @inheritdoc ICoordinatedTaker
    function submitLimitOrderFill(
        LimitOrder calldata order,
        bytes calldata makerSignature,
        uint256 takerTokenAmount,
        uint256 makerTokenAmount,
        bytes calldata extraAction,
        bytes calldata userTokenPermit,
        CoordinatorParams calldata crdParams
    ) external payable {
        // validate fill permission
        {
            if (crdParams.expiry < block.timestamp) revert ExpiredPermission();

            bytes32 orderHash = getLimitOrderHash(order);
            bytes32 allowFillHash = getEIP712Hash(
                getAllowFillHash(
                    AllowFill({ orderHash: orderHash, taker: msg.sender, fillAmount: makerTokenAmount, salt: crdParams.salt, expiry: crdParams.expiry })
                )
            );

            if (!SignatureValidator.validateSignature(coordinator, allowFillHash, crdParams.sig)) revert InvalidSignature();
            if (allowFillUsed[allowFillHash]) revert ReusedPermission();

            allowFillUsed[allowFillHash] = true;

            emit CoordinatorFill({ user: msg.sender, orderHash: orderHash, allowFillHash: allowFillHash });
        }

        // collect taker token from user (forward to LO contract without validation if taker token is ETH)
        if (!order.takerToken.isETH()) {
            if (msg.value != 0) revert InvalidMsgValue();
            _collect(order.takerToken, msg.sender, address(this), takerTokenAmount, userTokenPermit);
        }

        // send order to limit order contract
        // use fillLimitOrderFullOrKill since coordinator should manage fill amount distribution
        limitOrderSwap.fillLimitOrderFullOrKill{ value: msg.value }(
            order,
            makerSignature,
            ILimitOrderSwap.TakerParams({
                takerTokenAmount: takerTokenAmount,
                makerTokenAmount: makerTokenAmount,
                recipient: msg.sender,
                extraAction: extraAction,
                takerTokenPermit: abi.encodePacked(TokenCollector.Source.Token)
            })
        );
    }
}
