// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

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

/// @title RFQ Contract
/// @author imToken Labs
/// @notice This contract allows users to execute an RFQ (Request For Quote) order.
contract RFQ is IRFQ, Ownable, TokenCollector, EIP712 {
    using Asset for address;

    /// @dev Flag used to mark contract allowance in `RFQOffer.flag`.
    /// The left-most bit (bit 255) of the RFQOffer.flags represents whether the contract sender is allowed.
    uint256 private constant FLG_ALLOW_CONTRACT_SENDER = 1 << 255;

    /// @dev Flag used to mark partial fill allowance in `RFQOffer.flag`.
    /// The second left-most bit (bit 254) of the RFQOffer.flags represents whether partial fill is allowed.
    uint256 private constant FLG_ALLOW_PARTIAL_FILL = 1 << 254;

    /// @dev Flag used to mark market maker receives WETH in `RFQOffer.flag`.
    /// The third left-most bit (bit 253) of the RFQOffer.flags represents whether the market maker receives WETH.
    uint256 private constant FLG_MAKER_RECEIVES_WETH = 1 << 253;

    IWETH public immutable weth;
    address payable public feeCollector;

    /// @notice Mapping to track the filled status of each offer identified by its hash.
    mapping(bytes32 rfqOfferHash => bool isFilled) public filledOffer;

    /// @notice Constructor to initialize the RFQ contract with the owner, Uniswap permit2, allowance target, WETH, and fee collector.
    /// @param _owner The address of the contract owner.
    /// @param _uniswapPermit2 The address of the Uniswap permit2.
    /// @param _allowanceTarget The address of the allowance target.
    /// @param _weth The WETH token instance.
    /// @param _feeCollector The initial address of the fee collector.
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

    /// @notice Receive function to receive ETH.
    receive() external payable {}

    /// @notice Sets the fee collector address.
    /// @dev Only callable by the contract owner.
    /// @param _newFeeCollector The new address of the fee collector.
    function setFeeCollector(address payable _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert ZeroAddress();
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /// @inheritdoc IRFQ
    function fillRFQ(RFQTx calldata rfqTx, bytes calldata makerSignature, bytes calldata makerTokenPermit, bytes calldata takerTokenPermit) external payable {
        _fillRFQ(rfqTx, makerSignature, makerTokenPermit, takerTokenPermit, bytes(""));
    }

    /// @inheritdoc IRFQ
    function fillRFQWithSig(
        RFQTx calldata rfqTx,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature
    ) external {
        _fillRFQ(rfqTx, makerSignature, makerTokenPermit, takerTokenPermit, takerSignature);
    }

    /// @inheritdoc IRFQ
    function cancelRFQOffer(RFQOffer calldata rfqOffer) external {
        if (msg.sender != rfqOffer.maker) revert NotOfferMaker();
        bytes32 rfqOfferHash = getRFQOfferHash(rfqOffer);
        if (filledOffer[rfqOfferHash]) revert FilledRFQOffer();
        filledOffer[rfqOfferHash] = true;

        emit CancelRFQOffer(rfqOfferHash, rfqOffer.maker);
    }

    /// @dev Internal function to fill an RFQ transaction based on the provided parameters and signatures.
    /// @param _rfqTx The RFQ transaction data.
    /// @param _makerSignature The signature of the maker authorizing the transaction.
    /// @param _makerTokenPermit The permit data for the maker's token transfer.
    /// @param _takerTokenPermit The permit data for the taker's token transfer.
    /// @param _takerSignature The signature of the taker authorizing the transaction.
    function _fillRFQ(
        RFQTx calldata _rfqTx,
        bytes calldata _makerSignature,
        bytes calldata _makerTokenPermit,
        bytes calldata _takerTokenPermit,
        bytes memory _takerSignature
    ) private {
        RFQOffer memory _rfqOffer = _rfqTx.rfqOffer;

        // valid an RFQ offer
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

        // validate maker signature
        if (!SignatureValidator.validateSignature(_rfqOffer.maker, getEIP712Hash(rfqOfferHash), _makerSignature)) revert InvalidSignature();

        // validate taker signature if required
        if (_rfqOffer.taker != msg.sender) {
            if (!SignatureValidator.validateSignature(_rfqOffer.taker, getEIP712Hash(rfqTxHash), _takerSignature)) revert InvalidSignature();
        }

        // transfer takerToken to maker
        if (_rfqOffer.takerToken.isETH()) {
            if (msg.value != _rfqTx.takerRequestAmount) revert InvalidMsgValue();
            _collectETHAndSend(_rfqOffer.maker, _rfqTx.takerRequestAmount, ((_rfqOffer.flags & FLG_MAKER_RECEIVES_WETH) != 0));
        } else if (_rfqOffer.takerToken == address(weth)) {
            if (msg.value != 0) revert InvalidMsgValue();
            _collectWETHAndSend(
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

        // collect makerToken from maker to this contract
        uint256 makerSettleAmount = _rfqOffer.makerTokenAmount;
        if (_rfqTx.takerRequestAmount != _rfqOffer.takerTokenAmount) {
            makerSettleAmount = (_rfqTx.takerRequestAmount * _rfqOffer.makerTokenAmount) / _rfqOffer.takerTokenAmount;
        }
        if (makerSettleAmount == 0) revert InvalidMakerAmount();

        if (_rfqOffer.makerToken.isETH()) {
            // if the makerToken is ETH, we collect WETH from the maker to this contract
            _collect(address(weth), _rfqOffer.maker, address(this), makerSettleAmount, _makerTokenPermit);
        } else {
            // if the makerToken is a ERC20 token (including WETH) , we collect that ERC20 token from maker to this contract
            _collect(_rfqOffer.makerToken, _rfqOffer.maker, address(this), makerSettleAmount, _makerTokenPermit);
        }

        // calculate maker token settlement amount (minus fee)
        uint256 fee = (makerSettleAmount * _rfqOffer.feeFactor) / Constant.BPS_MAX;
        uint256 makerTokenToTaker;
        unchecked {
            // feeFactor is ensured <= Constant.BPS_MAX at the beginning so it's safe with unchecked block
            makerTokenToTaker = makerSettleAmount - fee;
        }

        {
            // unwrap WETH and send out ETH if makerToken is ETH
            address makerToken = _rfqOffer.makerToken;
            // after trying to withdraw more WETH than this contract has
            // and replacing `makerToken.isETH()` with `makerToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`
            // the if statement is still not fully covered by the test
            if (makerToken.isETH()) weth.withdraw(makerSettleAmount);

            // transfer fee to fee collector
            makerToken.transferTo(feeCollector, fee);
            // transfer maker token to recipient
            makerToken.transferTo(_rfqTx.recipient, makerTokenToTaker);
        }

        _emitFilledRFQEvent(rfqOfferHash, _rfqTx, makerTokenToTaker, fee);
    }

    /// @notice Emits the FilledRFQ event after executing an RFQ order swap.
    /// @param _rfqOfferHash The hash of the RFQ offer.
    /// @param _rfqTx The RFQ transaction data.
    /// @param _makerTokenToTaker The amount of maker tokens transferred to the taker.
    /// @param fee The fee amount collected.
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

    /// @notice Collects ETH and sends it to the specified address.
    /// @param to The address to send the collected ETH.
    /// @param amount The amount of ETH to collect.
    /// @param makerReceivesWETH Boolean flag to indicate if the maker receives WETH.
    function _collectETHAndSend(address payable to, uint256 amount, bool makerReceivesWETH) internal {
        if (makerReceivesWETH) {
            weth.deposit{ value: amount }();
            weth.transfer(to, amount);
        } else {
            // this branch cannot be covered because we cannot trigger the AddressInsufficientBalance error in sendValue,
            // as this function is called only when msg.value == amount
            Address.sendValue(to, amount);
        }
    }

    /// @notice Collects WETH and sends it to the specified address.
    /// @param from The address to collect WETH from.
    /// @param to The address to send the collected WETH.
    /// @param amount The amount of WETH to collect.
    /// @param data Additional data for the collection.
    /// @param makerReceivesWETH Boolean flag to indicate if the maker receives WETH.
    function _collectWETHAndSend(address from, address payable to, uint256 amount, bytes calldata data, bool makerReceivesWETH) internal {
        if (makerReceivesWETH) {
            _collect(address(weth), from, to, amount, data);
        } else {
            _collect(address(weth), from, address(this), amount, data);
            weth.withdraw(amount);
            Address.sendValue(to, amount);
        }
    }
}
