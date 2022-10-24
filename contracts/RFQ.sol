// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IRFQ.sol";
import "./utils/StrategyBase.sol";
import "./utils/RFQLibEIP712.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/SpenderLibEIP712.sol";
import "./utils/SignatureValidator.sol";
import "./utils/LibConstant.sol";

contract RFQ is IRFQ, StrategyBase, ReentrancyGuard, SignatureValidator, BaseLibEIP712 {
    using SafeMath for uint256;
    using Address for address;

    // Constants do not have storage slot.
    string public constant SOURCE = "RFQ v1";

    // Below are the variables which consume storage slots.
    address public feeCollector;

    struct GroupedVars {
        bytes32 orderHash;
        bytes32 transactionHash;
    }

    // Operator events
    event SetFeeCollector(address newFeeCollector);

    event FillOrder(
        string source,
        bytes32 indexed transactionHash,
        bytes32 indexed orderHash,
        address indexed userAddr,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint16 feeFactor
    );

    receive() external payable {}

    /************************************************************
     *              Constructor and init functions               *
     *************************************************************/
    constructor(
        address _owner,
        address _userProxy,
        address _weth,
        address _permStorage,
        address _spender,
        address _feeCollector
    ) StrategyBase(_owner, _userProxy, _weth, _permStorage, _spender) {
        feeCollector = _feeCollector;
    }

    /************************************************************
     *           Management functions for Operator               *
     *************************************************************/
    /**
     * @dev set fee collector
     */
    function setFeeCollector(address _newFeeCollector) external onlyOwner {
        require(_newFeeCollector != address(0), "RFQ: fee collector can not be zero address");
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    function fill(
        RFQLibEIP712.Order calldata _order,
        SpenderLibEIP712.SpendWithPermit calldata _spendMakerAssetToRFQ,
        SpenderLibEIP712.SpendWithPermit calldata _spendTakerAssetToRFQ,
        bytes calldata _mmSignature,
        bytes calldata _userSignature,
        bytes calldata _spendMakerAssetToRFQSig,
        bytes calldata _spendTakerAssetToRFQSig
    ) external payable override nonReentrant onlyUserProxy returns (uint256) {
        // check the order deadline and fee factor
        require(_order.deadline >= block.timestamp, "RFQ: expired order");
        require(_order.feeFactor < LibConstant.BPS_MAX, "RFQ: invalid fee factor");

        // check the spender deadline and RFQ address
        require(_spendMakerAssetToRFQ.expiry >= block.timestamp, "RFQ: expired maker spender");
        require(_spendMakerAssetToRFQ.requester == address(this), "RFQ: invalid RFQ address");
        require(_spendTakerAssetToRFQ.expiry >= block.timestamp, "RFQ: expired taker spender");
        require(_spendTakerAssetToRFQ.requester == address(this), "RFQ: invalid RFQ address");

        GroupedVars memory vars;

        // Validate signatures
        vars.orderHash = RFQLibEIP712._getOrderHash(_order);
        require(isValidSignature(_order.makerAddr, getEIP712Hash(vars.orderHash), bytes(""), _mmSignature), "RFQ: invalid MM signature");
        vars.transactionHash = RFQLibEIP712._getTransactionHash(_order);
        require(isValidSignature(_order.takerAddr, getEIP712Hash(vars.transactionHash), bytes(""), _userSignature), "RFQ: invalid user signature");

        // Set transaction as seen, PermanentStorage would throw error if transaction already seen.
        permStorage.setRFQTransactionSeen(vars.transactionHash);

        return
            _settle({
                _order: _order,
                _spendMakerAssetToRFQ: _spendMakerAssetToRFQ,
                _spendTakerAssetToRFQ: _spendTakerAssetToRFQ,
                _vars: vars,
                _spendMakerAssetToRFQSig: _spendMakerAssetToRFQSig,
                _spendTakerAssetToRFQSig: _spendTakerAssetToRFQSig
            });
    }

    function _emitFillOrder(
        RFQLibEIP712.Order memory _order,
        GroupedVars memory _vars,
        uint256 settleAmount
    ) internal {
        emit FillOrder(
            SOURCE,
            _vars.transactionHash,
            _vars.orderHash,
            _order.takerAddr,
            _order.takerAssetAddr,
            _order.takerAssetAmount,
            _order.makerAddr,
            _order.makerAssetAddr,
            _order.makerAssetAmount,
            _order.receiverAddr,
            settleAmount,
            uint16(_order.feeFactor)
        );
    }

    // settle
    function _settle(
        RFQLibEIP712.Order memory _order,
        SpenderLibEIP712.SpendWithPermit memory _spendMakerAssetToRFQ,
        SpenderLibEIP712.SpendWithPermit memory _spendTakerAssetToRFQ,
        GroupedVars memory _vars,
        bytes memory _spendMakerAssetToRFQSig,
        bytes memory _spendTakerAssetToRFQSig
    ) internal returns (uint256) {
        // Transfer taker asset to maker
        if (address(weth) == _order.takerAssetAddr) {
            // Deposit to WETH if taker asset is ETH
            require(msg.value == _order.takerAssetAmount, "RFQ: insufficient ETH");
            weth.deposit{ value: msg.value }();
            weth.transfer(_order.makerAddr, _order.takerAssetAmount);
        } else {
            require(
                // Confirm that 'takerAddr' sends 'takerAssetAmount' amount of 'takerAssetAddr' to 'address(this)'
                _order.takerAddr == _spendTakerAssetToRFQ.user &&
                    _order.takerAssetAddr == _spendTakerAssetToRFQ.tokenAddr &&
                    address(this) == _spendTakerAssetToRFQ.recipient &&
                    _order.takerAssetAmount == _spendTakerAssetToRFQ.amount,
                "RFQ: taker spender information is incorrect"
            );
            // Transfer taker asset to RFQ (= this) first,
            spender.spendFromUserToWithPermit({
                _tokenAddr: _spendTakerAssetToRFQ.tokenAddr,
                _requester: _spendTakerAssetToRFQ.requester,
                _user: _spendTakerAssetToRFQ.user,
                _recipient: _spendTakerAssetToRFQ.recipient,
                _amount: _spendTakerAssetToRFQ.amount,
                _salt: _spendTakerAssetToRFQ.salt,
                _expiry: _spendTakerAssetToRFQ.expiry,
                _spendWithPermitSig: _spendTakerAssetToRFQSig
            });
            // then transfer from this to maker.
            IERC20(_order.takerAssetAddr).transfer(_order.makerAddr, _order.takerAssetAmount);
        }

        // Transfer maker asset to taker, sub fee
        uint256 fee = _order.makerAssetAmount.mul(_order.feeFactor).div(LibConstant.BPS_MAX);
        uint256 settleAmount = _order.makerAssetAmount;
        if (fee > 0) {
            settleAmount = settleAmount.sub(fee);
        }

        require(
            // Confirm that 'makerAddr' sends 'makerAssetAmount' amount of 'makerAssetAddr' to 'address(this)'
            _order.makerAddr == _spendMakerAssetToRFQ.user &&
                _order.makerAssetAddr == _spendMakerAssetToRFQ.tokenAddr &&
                address(this) == _spendMakerAssetToRFQ.recipient &&
                _order.makerAssetAmount == _spendMakerAssetToRFQ.amount,
            "RFQ: maker spender information is incorrect"
        );
        // Transfer maker asset to RFQ (= this) first,
        spender.spendFromUserToWithPermit({
            _tokenAddr: _spendMakerAssetToRFQ.tokenAddr,
            _requester: _spendMakerAssetToRFQ.requester,
            _user: _spendMakerAssetToRFQ.user,
            _recipient: _spendMakerAssetToRFQ.recipient,
            _amount: _spendMakerAssetToRFQ.amount,
            _salt: _spendMakerAssetToRFQ.salt,
            _expiry: _spendMakerAssetToRFQ.expiry,
            _spendWithPermitSig: _spendMakerAssetToRFQSig
        });

        // then transfer maker asset (but except fee) from this to receiver,
        if (_order.makerAssetAddr == address(weth)) {
            weth.withdraw(settleAmount);
            payable(_order.receiverAddr).transfer(settleAmount);
        } else {
            IERC20(_order.makerAssetAddr).transfer(_order.receiverAddr, settleAmount);
        }

        // and transfer fee from this to feeCollector.
        if (fee > 0) {
            IERC20(_order.makerAssetAddr).transfer(feeCollector, fee);
        }

        _emitFillOrder(_order, _vars, settleAmount);

        return settleAmount;
    }
}
