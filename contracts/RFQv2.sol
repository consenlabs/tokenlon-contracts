// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TokenCollector } from "./utils/TokenCollector.sol";
import { BaseLibEIP712 } from "./utils/BaseLibEIP712.sol";
import { Asset } from "./utils/Asset.sol";
import { Offer, getOfferHash } from "./utils/Offer.sol";
import { RFQOrder, getRFQOrderHash } from "./utils/RFQOrder.sol";
import { LibConstant } from "./utils/LibConstant.sol";
import { SignatureValidator } from "./utils/SignatureValidator.sol";
import { StrategyBase } from "./utils/StrategyBase.sol";
import { IRFQv2 } from "./interfaces/IRFQv2.sol";

/// @title RFQv2 Contract
/// @author imToken Labs
contract RFQv2 is IRFQv2, StrategyBase, TokenCollector, SignatureValidator, BaseLibEIP712 {
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
        _fillRFQ(order, makerSignature, makerTokenPermit, takerSignature, takerTokenPermit);
    }

    function _fillRFQ(
        RFQOrder memory _rfqOrder,
        bytes memory _makerSignature,
        bytes memory _makerTokenPermit,
        bytes memory _takerSignature,
        bytes memory _takerTokenPermit
    ) private {
        Offer memory _offer = _rfqOrder.offer;
        // check the offer deadline and fee factor
        require(_offer.expiry >= block.timestamp, "offer expired");
        require(_rfqOrder.feeFactor < LibConstant.BPS_MAX, "invalid fee factor");

        // check if the offer is available to be filled
        (bytes32 offerHash, bytes32 rfqOrderHash) = getRFQOrderHash(_rfqOrder);

        // check and set
        permStorage.setRFQOfferFilled(offerHash);

        // check maker signature
        require(isValidSignature(_offer.maker, getEIP712Hash(offerHash), bytes(""), _makerSignature), "invalid signature");

        // check taker signature if needed
        if (_offer.taker != msg.sender) {
            require(isValidSignature(_offer.taker, getEIP712Hash(rfqOrderHash), bytes(""), _takerSignature), "invalid signature");
        }

        // transfer takerToken to maker
        if (_offer.takerToken.isETH()) {
            require(msg.value == _offer.takerTokenAmount, "invalid msg value");
            Address.sendValue(_offer.maker, _offer.takerTokenAmount);
        } else if (_offer.takerToken == address(weth)) {
            _collect(_offer.takerToken, _offer.taker, address(this), _offer.takerTokenAmount, _takerTokenPermit);
            weth.withdraw(_offer.takerTokenAmount);
            Address.sendValue(_offer.maker, _offer.takerTokenAmount);
        } else {
            _collect(_offer.takerToken, _offer.taker, _offer.maker, _offer.takerTokenAmount, _takerTokenPermit);
        }

        // collect makerToken from maker to this
        _collect(_offer.makerToken, _offer.maker, address(this), _offer.makerTokenAmount, _makerTokenPermit);

        // transfer makerToken to recipient (sub fee)
        uint256 fee = _offer.makerTokenAmount.mul(_rfqOrder.feeFactor).div(LibConstant.BPS_MAX);
        // determine if WETH unwrap is needed, send out ETH if makerToken is WETH
        address makerToken = _offer.makerToken;
        if (makerToken == address(weth)) {
            weth.withdraw(_offer.makerTokenAmount);
            makerToken = LibConstant.ETH_ADDRESS;
        }
        uint256 makerTokenToTaker = _offer.makerTokenAmount.sub(fee);

        // collect fee if present
        if (fee > 0) {
            makerToken.transferTo(feeCollector, fee);
        }

        makerToken.transferTo(_rfqOrder.recipient, makerTokenToTaker);

        _emitFilledRFQEvent(offerHash, _rfqOrder, makerTokenToTaker);
    }

    function _emitFilledRFQEvent(
        bytes32 _offerHash,
        RFQOrder memory _rfqOrder,
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
            _rfqOrder.feeFactor
        );
    }
}
