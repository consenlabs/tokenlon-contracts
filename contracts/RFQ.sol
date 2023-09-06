// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IRFQ } from "./interfaces/IRFQ.sol";
import { Asset } from "./libraries/Asset.sol";
import { RFQOffer, getRFQOfferHash } from "./libraries/RFQOffer.sol";
import { RFQTx, getRFQTxHash } from "./libraries/RFQTx.sol";
import { Constant } from "./libraries/Constant.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract RFQ is IRFQ, Ownable, TokenCollector, EIP712 {
    using Asset for address;

    uint256 private constant FLG_ALLOW_CONTRACT_SENDER = 1 << 255;
    uint256 private constant FLG_ALLOW_PARTIAL_FILL = 1 << 254;
    uint256 private constant FLG_MAKER_RECEIVES_WETH = 1 << 253;

    IWETH public immutable weth;
    address payable public feeCollector;

    mapping(bytes32 => bool) private filledOffer;

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
        if (_feeCollector == address(0)) revert ZeroAddress();
        feeCollector = _feeCollector;
    }

    receive() external payable {}

    /// @notice Set fee collector
    /// @notice Only owner can call
    /// @param _newFeeCollector The address of the new fee collector
    function setFeeCollector(address payable _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert ZeroAddress();
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    function fillRFQ(
        RFQTx calldata rfqTx,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit
    ) external payable override {
        _fillRFQ(rfqTx, makerSignature, makerTokenPermit, takerTokenPermit, bytes(""));
    }

    function fillRFQ(
        RFQTx calldata rfqTx,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature
    ) external override {
        _fillRFQ(rfqTx, makerSignature, makerTokenPermit, takerTokenPermit, takerSignature);
    }

    function cancelRFQOffer(RFQOffer calldata rfqOffer) external override {
        if (msg.sender != rfqOffer.maker) revert NotOfferMaker();
        bytes32 rfqOfferHash = getRFQOfferHash(rfqOffer);
        if (filledOffer[rfqOfferHash]) revert FilledRFQOffer();
        filledOffer[rfqOfferHash] = true;

        emit CancelRFQOffer(rfqOfferHash, rfqOffer.maker);
    }

    function _fillRFQ(
        RFQTx calldata _rfqTx,
        bytes calldata _makerSignature,
        bytes calldata _makerTokenPermit,
        bytes calldata _takerTokenPermit,
        bytes memory _takerSignature
    ) private {
        RFQOffer memory _rfqOffer = _rfqTx.rfqOffer;
        // check the offer deadline and fee factor
        if (_rfqOffer.expiry < block.timestamp) revert ExpiredRFQOffer();
        if (_rfqOffer.flags & FLG_ALLOW_CONTRACT_SENDER == 0) {
            if (msg.sender != tx.origin) revert ForbidContract();
        }
        if (_rfqOffer.flags & FLG_ALLOW_PARTIAL_FILL == 0) {
            if (_rfqTx.takerRequestAmount != _rfqOffer.takerTokenAmount) revert ForbidPartialFill();
        }
        if (_rfqOffer.feeFactor > Constant.BPS_MAX) revert InvalidFeeFactor();
        if (_rfqTx.recipient == address(0)) revert ZeroAddress();
        if (_rfqTx.takerRequestAmount > _rfqOffer.takerTokenAmount || _rfqTx.takerRequestAmount == 0) revert InvalidTakerAmount();

        // check if the offer is available to be filled
        (bytes32 rfqOfferHash, bytes32 rfqTxHash) = getRFQTxHash(_rfqTx);
        if (filledOffer[rfqOfferHash]) revert FilledRFQOffer();
        filledOffer[rfqOfferHash] = true;

        // check maker signature
        if (!SignatureValidator.validateSignature(_rfqOffer.maker, getEIP712Hash(rfqOfferHash), _makerSignature)) revert InvalidSignature();

        // check taker signature if needed
        if (_rfqOffer.taker != msg.sender) {
            if (!SignatureValidator.validateSignature(_rfqOffer.taker, getEIP712Hash(rfqTxHash), _takerSignature)) revert InvalidSignature();
        }

        // transfer takerToken to maker
        if (_rfqOffer.takerToken.isETH()) {
            if (msg.value != _rfqTx.takerRequestAmount) revert InvalidMsgValue();
            _collecETHAndSend(_rfqOffer.maker, _rfqTx.takerRequestAmount, ((_rfqOffer.flags & FLG_MAKER_RECEIVES_WETH) != 0));
        } else if (_rfqOffer.takerToken == address(weth)) {
            if (msg.value != 0) revert InvalidMsgValue();
            _collecWETHAndSend(
                _rfqOffer.taker,
                _rfqOffer.maker,
                _rfqTx.takerRequestAmount,
                _takerTokenPermit,
                ((_rfqOffer.flags & FLG_MAKER_RECEIVES_WETH) != 0)
            );
        } else {
            if (msg.value != 0) revert InvalidMsgValue();
            _collect(_rfqOffer.takerToken, _rfqOffer.taker, _rfqOffer.maker, _rfqTx.takerRequestAmount, _takerTokenPermit);
        }

        // collect makerToken from maker to this
        uint256 makerSettleAmount = _rfqOffer.makerTokenAmount;
        if (_rfqTx.takerRequestAmount != _rfqOffer.takerTokenAmount) {
            makerSettleAmount = (_rfqTx.takerRequestAmount * _rfqOffer.makerTokenAmount) / _rfqOffer.takerTokenAmount;
        }
        if (makerSettleAmount == 0) revert InvalidMakerAmount();
        _collect(_rfqOffer.makerToken, _rfqOffer.maker, address(this), makerSettleAmount, _makerTokenPermit);

        // calculate maker token settlement amount (sub fee)
        uint256 fee = (makerSettleAmount * _rfqOffer.feeFactor) / Constant.BPS_MAX;
        uint256 makerTokenToTaker;
        unchecked {
            // feeFactor is ensured <= Constant.BPS_MAX at the beginning so it's safe with unchecked block
            makerTokenToTaker = makerSettleAmount - fee;
        }

        {
            // determine if WETH unwrap is needed, send out ETH if makerToken is WETH
            address makerToken = _rfqOffer.makerToken;
            if (makerToken == address(weth)) {
                weth.withdraw(makerSettleAmount);
                makerToken = Constant.ETH_ADDRESS;
            }

            // collect fee
            makerToken.transferTo(feeCollector, fee);
            // transfer maker token to recipient
            makerToken.transferTo(_rfqTx.recipient, makerTokenToTaker);
        }

        _emitFilledRFQEvent(rfqOfferHash, _rfqTx, makerTokenToTaker, fee);
    }

    function _emitFilledRFQEvent(bytes32 _rfqOfferHash, RFQTx calldata _rfqTx, uint256 _makerTokenToTaker, uint256 fee) internal {
        emit FilledRFQ(
            _rfqOfferHash,
            _rfqTx.rfqOffer.taker,
            _rfqTx.rfqOffer.maker,
            _rfqTx.rfqOffer.takerToken,
            _rfqTx.takerRequestAmount,
            _rfqTx.rfqOffer.makerToken,
            _makerTokenToTaker,
            _rfqTx.recipient,
            fee
        );
    }

    // Only used when taker token is ETH
    function _collecETHAndSend(address payable to, uint256 amount, bool makerReceivesWETH) internal {
        if (makerReceivesWETH) {
            weth.deposit{ value: amount }();
            weth.transfer(to, amount);
        } else {
            Address.sendValue(to, amount);
        }
    }

    // Only used when taker token is WETH
    function _collecWETHAndSend(address from, address payable to, uint256 amount, bytes calldata data, bool makerReceivesWETH) internal {
        if (makerReceivesWETH) {
            _collect(address(weth), from, to, amount, data);
        } else {
            _collect(address(weth), from, address(this), amount, data);
            weth.withdraw(amount);
            Address.sendValue(to, amount);
        }
    }
}
