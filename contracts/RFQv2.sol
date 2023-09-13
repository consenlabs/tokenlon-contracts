// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TokenCollector } from "./utils/TokenCollector.sol";
import { BaseLibEIP712 } from "./utils/BaseLibEIP712.sol";
import { Asset } from "./utils/Asset.sol";
import { Offer } from "./utils/Offer.sol";
import { RFQOrder, getRFQOrderHash } from "./utils/RFQOrder.sol";
import { LibConstant } from "./utils/LibConstant.sol";
import { validateSignature } from "./utils/SignatureValidator.sol";
import { StrategyBase } from "./utils/StrategyBase.sol";
import { IRFQv2 } from "./interfaces/IRFQv2.sol";

/// @title RFQv2 Contract
/// @author imToken Labs
contract RFQv2 is IRFQv2, StrategyBase, TokenCollector, BaseLibEIP712 {
    using SafeMath for uint256;
    using Asset for address;

    address payable public feeCollector;

    /// @notice Emitted when fee collector address is updated
    /// @param newFeeCollector The address of the new fee collector
    event SetFeeCollector(address newFeeCollector);

    receive() external payable {}

    constructor(
        address _owner,
        address _userProxy,
        address _weth,
        address _permStorage,
        address _spender,
        address _uniswapPermit2,
        address payable _feeCollector
    ) StrategyBase(_owner, _userProxy, _weth, _permStorage, _spender) TokenCollector(_uniswapPermit2, _spender) {
        feeCollector = _feeCollector;
    }

    /// @notice Set fee collector
    /// @notice Only owner can call
    /// @param _newFeeCollector The address of the new fee collector
    function setFeeCollector(address payable _newFeeCollector) external onlyOwner {
        require(_newFeeCollector != address(0), "zero address");
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /// @inheritdoc IRFQv2
    function fillRFQ(
        RFQOrder calldata order,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerSignature,
        bytes calldata takerTokenPermit
    ) external payable override onlyUserProxy {
        Offer calldata _offer = order.offer;
        // check the offer deadline and fee factor
        require(_offer.expiry > block.timestamp, "offer expired");
        require(_offer.feeFactor < LibConstant.BPS_MAX, "invalid fee factor");
        require(order.recipient != address(0), "zero recipient");

        // check if the offer is available to be filled
        (bytes32 offerHash, bytes32 rfqOrderHash) = getRFQOrderHash(order);

        // check and set
        permStorage.setRFQOfferFilled(offerHash);

        // check maker signature
        require(validateSignature(_offer.maker, getEIP712Hash(offerHash), makerSignature), "invalid signature");

        // check taker signature if needed
        if (_offer.taker != msg.sender) {
            require(validateSignature(_offer.taker, getEIP712Hash(rfqOrderHash), takerSignature), "invalid signature");
        }

        // transfer takerToken to maker
        if (_offer.takerToken.isETH()) {
            require(msg.value == _offer.takerTokenAmount, "invalid msg value");
            weth.deposit{ value: msg.value }();
            weth.transfer(_offer.maker, msg.value);
        } else {
            require(msg.value == 0, "invalid msg value");
            _collect(_offer.takerToken, _offer.taker, _offer.maker, _offer.takerTokenAmount, takerTokenPermit);
        }

        // collect makerToken from maker to this
        _collect(_offer.makerToken, _offer.maker, address(this), _offer.makerTokenAmount, makerTokenPermit);

        // transfer makerToken to recipient (sub fee)
        uint256 fee = _offer.makerTokenAmount.mul(_offer.feeFactor).div(LibConstant.BPS_MAX);
        uint256 makerTokenToTaker = _offer.makerTokenAmount.sub(fee);
        {
            // determine if WETH unwrap is needed, send out ETH if makerToken is WETH
            address makerToken = _offer.makerToken;
            if (makerToken == address(weth)) {
                weth.withdraw(_offer.makerTokenAmount);
                makerToken = LibConstant.ETH_ADDRESS;
            }

            // collect fee if present
            if (fee > 0) {
                makerToken.transferTo(feeCollector, fee);
            }

            makerToken.transferTo(order.recipient, makerTokenToTaker);
        }

        _emitFilledRFQEvent(offerHash, order, makerTokenToTaker);
    }

    function _emitFilledRFQEvent(
        bytes32 _offerHash,
        RFQOrder calldata _rfqOrder,
        uint256 _makerTokenToTaker
    ) internal {
        emit FilledRFQ(
            _offerHash,
            _rfqOrder.offer.taker,
            _rfqOrder.offer.maker,
            _rfqOrder.offer.takerToken,
            _rfqOrder.offer.takerTokenAmount,
            _rfqOrder.offer.makerToken,
            _rfqOrder.offer.makerTokenAmount,
            _rfqOrder.recipient,
            _makerTokenToTaker,
            _rfqOrder.offer.feeFactor
        );
    }
}
