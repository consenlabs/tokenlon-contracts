// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IWETH } from "./interfaces/IWeth.sol";
import { IRFQ } from "./interfaces/IRFQ.sol";
import { Asset } from "./libraries/Asset.sol";
import { Offer } from "./libraries/Offer.sol";
import { RFQOrder, getRFQOrderHash } from "./libraries/RFQOrder.sol";
import { Constant } from "./libraries/Constant.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract RFQ is IRFQ, Ownable, TokenCollector, EIP712 {
    using Asset for address;

    IWETH public immutable weth;
    address payable public feeCollector;

    mapping(bytes32 => bool) private filledOffer;

    /// @notice Emitted when fee collector address is updated
    /// @param newFeeCollector The address of the new fee collector
    event SetFeeCollector(address newFeeCollector);

    receive() external payable {}

    constructor(
        address _owner,
        address _uniswapPermit2,
        IWETH _weth,
        address payable _feeCollector
    ) Ownable(_owner) TokenCollector(_uniswapPermit2) {
        weth = _weth;
        feeCollector = _feeCollector;
    }

    /// @notice Set fee collector
    /// @notice Only owner can call
    /// @param _newFeeCollector The address of the new fee collector
    function setFeeCollector(address payable _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert ZeroAddress();
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    function fillRFQ(
        Offer calldata offer,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        address payable recipient
    ) external payable override {
        _fillRFQ(RFQOrder({ offer: offer, recipient: recipient, feeFactor: 0 }), makerSignature, makerTokenPermit, takerTokenPermit, bytes(""));
    }

    function fillRFQ(
        RFQOrder calldata order,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature
    ) external override {
        _fillRFQ(order, makerSignature, makerTokenPermit, takerTokenPermit, takerSignature);
    }

    function _fillRFQ(
        RFQOrder memory _rfqOrder,
        bytes memory _makerSignature,
        bytes memory _makerTokenPermit,
        bytes memory _takerTokenPermit,
        bytes memory _takerSignature
    ) private {
        Offer memory _offer = _rfqOrder.offer;
        // check the offer deadline and fee factor
        if (_offer.expiry < block.timestamp) revert ExpiredOffer();
        if (_rfqOrder.feeFactor > Constant.BPS_MAX) revert InvalidFeeFactor();

        // check if the offer is available to be filled
        (bytes32 offerHash, bytes32 rfqOrderHash) = getRFQOrderHash(_rfqOrder);
        if (filledOffer[offerHash]) revert FilledOffer();
        filledOffer[offerHash] = true;

        // check maker signature
        if (!SignatureValidator.isValidSignature(_offer.maker, getEIP712Hash(offerHash), _makerSignature)) revert InvalidSignature();

        // check taker signature if needed
        if (_offer.taker != msg.sender) {
            if (!SignatureValidator.isValidSignature(_offer.taker, getEIP712Hash(rfqOrderHash), _takerSignature)) revert InvalidSignature();
        }

        // transfer takerToken to maker
        if (_offer.takerToken.isETH()) {
            if (msg.value != _offer.takerTokenAmount) revert InvalidMsgValue();
            Address.sendValue(_offer.maker, _offer.takerTokenAmount);
        } else {
            _collect(_offer.takerToken, _offer.taker, _offer.maker, _offer.takerTokenAmount, _takerTokenPermit);
        }

        // collect makerToken from maker to this
        _collect(_offer.makerToken, _offer.maker, address(this), _offer.makerTokenAmount, _makerTokenPermit);

        // transfer makerToken to recipient (sub fee)
        uint256 fee = (_offer.makerTokenAmount * _rfqOrder.feeFactor) / Constant.BPS_MAX;
        // determine if WETH unwrap is needed, send out ETH if makerToken is WETH
        address makerToken = _offer.makerToken;
        if (makerToken == address(weth)) {
            weth.withdraw(_offer.makerTokenAmount);
            makerToken = Constant.ETH_ADDRESS;
        }
        uint256 makerTokenToTaker = _offer.makerTokenAmount - fee;
        makerToken.transferTo(_rfqOrder.recipient, makerTokenToTaker);

        // collect fee if present
        if (fee > 0) {
            makerToken.transferTo(feeCollector, fee);
        }

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
