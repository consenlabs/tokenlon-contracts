// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { TokenCollector } from "./abstracts/TokenCollector.sol";
import { Ownable } from "./abstracts/Ownable.sol";
import { EIP712 } from "./abstracts/EIP712.sol";
import { IWETH } from "./interfaces/IWeth.sol";
import { IRFQ } from "./interfaces/IRFQ.sol";
import { Asset } from "./libraries/Asset.sol";
import { Order, getOrderHash } from "./libraries/Order.sol";
import { Constant } from "./libraries/Constant.sol";
import { SignatureValidator } from "./libraries/SignatureValidator.sol";

contract RFQ is IRFQ, Ownable, TokenCollector, EIP712 {
    using SafeERC20 for IERC20;
    using Asset for address;

    bytes32 public constant RFQ_ORDER_TYPEHASH = 0xd4e740a3a31cb8bb7c1c5b2f40e6fad5b83a7b1090bba797c6d040eac07ecda7;
    // keccak256(abi.encodePacked("RFQOrder(Order order,uint256 feeFactor)", ORDER_TYPESTRING));

    IWETH public immutable weth;
    address payable public feeCollector;

    mapping(bytes32 => bool) private filledRFQOrder;

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
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit
    ) external payable override {
        _fillRFQ(rfqOrder, makerSignature, makerTokenPermit, takerTokenPermit, bytes(""));
    }

    function fillRFQ(
        RFQOrder calldata rfqOrder,
        bytes calldata makerSignature,
        bytes calldata makerTokenPermit,
        bytes calldata takerTokenPermit,
        bytes calldata takerSignature,
        address taker
    ) external override {
        if (rfqOrder.order.taker != taker) revert InvalidTaker();
        _fillRFQ(rfqOrder, makerSignature, makerTokenPermit, takerTokenPermit, takerSignature);
    }

    function _fillRFQ(
        RFQOrder memory _rfqOrder,
        bytes memory _makerSignature,
        bytes memory _makerTokenPermit,
        bytes memory _takerTokenPermit,
        bytes memory _takerSignature
    ) private {
        Order memory _order = _rfqOrder.order;
        // check the order deadline and fee factor
        if (_order.expiry < block.timestamp) revert ExpiredOrder();
        if (_rfqOrder.feeFactor > Constant.BPS_MAX) revert InvalidFeeFactor();

        // check if the order is available to be filled
        bytes32 rfqOrderHash = _getRFQOrderHash(_rfqOrder);
        if (filledRFQOrder[rfqOrderHash]) revert FilledOrder();
        filledRFQOrder[rfqOrderHash] = true;
        // EIP-712 hash
        bytes32 sigHash = getEIP712Hash(rfqOrderHash);

        // check maker signature
        if (!SignatureValidator.isValidSignature(_order.maker, sigHash, _makerSignature)) revert InvalidSignature();

        // check taker signature if needed
        if (_order.taker != msg.sender) {
            if (!SignatureValidator.isValidSignature(_order.taker, sigHash, _takerSignature)) revert InvalidSignature();
        }

        // transfer takerToken to maker
        if (_order.takerToken.isETH()) {
            if (msg.value != _order.takerTokenAmount) revert InvalidMsgValue();
            Address.sendValue(_order.maker, _order.takerTokenAmount);
        } else {
            _collect(_order.takerToken, _order.taker, _order.maker, _order.takerTokenAmount, _takerTokenPermit);
        }

        // collect makerToken from maker to this
        _collect(_order.makerToken, _order.maker, address(this), _order.makerTokenAmount, _makerTokenPermit);

        // transfer makerToken to recipient (sub fee)
        uint256 fee = (_order.makerTokenAmount * _rfqOrder.feeFactor) / Constant.BPS_MAX;
        // determine if WETH unwrap is needed, send out ETH if makerToken is WETH
        address makerToken = _order.makerToken;
        if (makerToken == address(weth)) {
            weth.withdraw(_order.makerTokenAmount);
            makerToken = Constant.ETH_ADDRESS;
        }
        uint256 makerTokenToTaker = _order.makerTokenAmount - fee;
        makerToken.transferTo(_order.recipient, makerTokenToTaker);

        // collect fee if present
        if (fee > 0) {
            makerToken.transferTo(feeCollector, fee);
        }

        _emitEvent(rfqOrderHash, _rfqOrder, makerTokenToTaker);
    }

    function _getRFQOrderHash(RFQOrder memory rfqOrder) private pure returns (bytes32) {
        bytes32 orderHash = getOrderHash(rfqOrder.order);
        return keccak256(abi.encode(RFQ_ORDER_TYPEHASH, orderHash, rfqOrder.feeFactor));
    }

    function _emitEvent(
        bytes32 _rfqOrderHash,
        RFQOrder memory _rfqOrder,
        uint256 _makerTokenToTaker
    ) internal {
        emit FilledRFQ(
            _rfqOrderHash,
            _rfqOrder.order.taker,
            _rfqOrder.order.maker,
            _rfqOrder.order.takerToken,
            _rfqOrder.order.takerTokenAmount,
            _rfqOrder.order.makerToken,
            _rfqOrder.order.makerTokenAmount,
            _rfqOrder.order.recipient,
            _makerTokenToTaker,
            _rfqOrder.feeFactor
        );
    }
}
