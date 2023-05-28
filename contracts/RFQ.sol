// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
        address _allowanceTarget,
        IWETH _weth,
        address payable _feeCollector
    ) Ownable(_owner) TokenCollector(_uniswapPermit2, _allowanceTarget) {
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
        RFQOffer calldata rfqOffer,
        uint256 takerRequestAmount,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        address payable recipient,
        uint256 feeFactor
    ) external payable override {
        _fillRFQ(
            RFQTx({ rfqOffer: rfqOffer, takerRequestAmount: takerRequestAmount, recipient: recipient, feeFactor: feeFactor }),
            makerSignature,
            makerTokenPermit,
            takerTokenPermit,
            bytes("")
        );
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
        filledOffer[rfqOfferHash] = true;

        emit CancelRFQOffer(rfqOfferHash, rfqOffer.maker);
    }

    function _fillRFQ(
        RFQTx memory _rfqTx,
        bytes memory _makerSignature,
        bytes memory _makerTokenPermit,
        bytes memory _takerTokenPermit,
        bytes memory _takerSignature
    ) private {
        RFQOffer memory _rfqOffer = _rfqTx.rfqOffer;
        // check the offer deadline and fee factor
        if (_rfqOffer.expiry < block.timestamp) revert ExpiredRFQOffer();
        if ((_rfqOffer.flags & FLG_ALLOW_CONTRACT_SENDER == 0) && (msg.sender != tx.origin)) revert ForbidContract();
        if ((_rfqOffer.flags & FLG_ALLOW_PARTIAL_FILL == 0) && (_rfqTx.takerRequestAmount != _rfqOffer.takerTokenAmount)) revert ForbidPartialFill();
        if (_rfqTx.feeFactor > Constant.BPS_MAX) revert InvalidFeeFactor();
        if (_rfqTx.recipient == address(0)) revert ZeroAddress();
        if (_rfqTx.takerRequestAmount > _rfqOffer.takerTokenAmount || _rfqTx.takerRequestAmount == 0) revert InvalidTakerAmount();

        // check if the offer is available to be filled
        (bytes32 rfqOfferHash, bytes32 rfqTxHash) = getRFQTxHash(_rfqTx);
        if (filledOffer[rfqOfferHash]) revert FilledRFQOffer();
        filledOffer[rfqOfferHash] = true;

        // check maker signature
        if (!SignatureValidator.isValidSignature(_rfqOffer.maker, getEIP712Hash(rfqOfferHash), _makerSignature)) revert InvalidSignature();

        // check taker signature if needed
        if (_rfqOffer.taker != msg.sender) {
            if (!SignatureValidator.isValidSignature(_rfqOffer.taker, getEIP712Hash(rfqTxHash), _takerSignature)) revert InvalidSignature();
        }

        // transfer takerToken to maker
        if (_rfqOffer.takerToken.isETH()) {
            if (msg.value != _rfqTx.takerRequestAmount) revert InvalidMsgValue();
            Address.sendValue(_rfqOffer.maker, _rfqTx.takerRequestAmount);
        } else if (_rfqOffer.takerToken == address(weth)) {
            if (msg.value != 0) revert InvalidMsgValue();
            _collect(_rfqOffer.takerToken, _rfqOffer.taker, address(this), _rfqTx.takerRequestAmount, _takerTokenPermit);
            weth.withdraw(_rfqTx.takerRequestAmount);
            Address.sendValue(_rfqOffer.maker, _rfqTx.takerRequestAmount);
        } else {
            if (msg.value != 0) revert InvalidMsgValue();
            _collect(_rfqOffer.takerToken, _rfqOffer.taker, _rfqOffer.maker, _rfqTx.takerRequestAmount, _takerTokenPermit);
        }

        // collect makerToken from maker to this
        uint256 makerHelloAmount = _rfqOffer.makerTokenAmount;
        if (_rfqTx.takerRequestAmount != _rfqOffer.takerTokenAmount) {
            makerHelloAmount = (_rfqTx.takerRequestAmount * _rfqOffer.makerTokenAmount) / _rfqOffer.takerTokenAmount;
        }
        _collect(_rfqOffer.makerToken, _rfqOffer.maker, address(this), makerHelloAmount, _makerTokenPermit);

        // transfer makerToken to recipient (sub fee)
        uint256 fee = (makerHelloAmount * _rfqTx.feeFactor) / Constant.BPS_MAX;
        // determine if WETH unwrap is needed, send out ETH if makerToken is WETH
        address makerToken = _rfqOffer.makerToken;
        if (makerToken == address(weth)) {
            weth.withdraw(makerHelloAmount);
            makerToken = Constant.ETH_ADDRESS;
        }
        uint256 makerTokenToTaker = makerHelloAmount - fee;

        // collect fee
        makerToken.transferTo(feeCollector, fee);

        makerToken.transferTo(_rfqTx.recipient, makerTokenToTaker);

        _emitFilledRFQEvent(rfqOfferHash, _rfqTx, makerTokenToTaker);
    }

    function _emitFilledRFQEvent(
        bytes32 _rfqOfferHash,
        RFQTx memory _rfqTx,
        uint256 _makerTokenToTaker
    ) internal {
        emit FilledRFQ(
            _rfqOfferHash,
            _rfqTx.rfqOffer.taker,
            _rfqTx.rfqOffer.maker,
            _rfqTx.rfqOffer.takerToken,
            _rfqTx.rfqOffer.takerTokenAmount,
            _rfqTx.rfqOffer.makerToken,
            _rfqTx.rfqOffer.makerTokenAmount,
            _rfqTx.recipient,
            _makerTokenToTaker,
            _rfqTx.feeFactor
        );
    }
}
