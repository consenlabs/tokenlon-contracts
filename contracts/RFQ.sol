// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IRFQ.sol";
import "./utils/StrategyBase.sol";
import "./utils/RFQLibEIP712.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/SignatureValidator.sol";
import "./utils/LibConstant.sol";

contract RFQ is IRFQ, StrategyBase, ReentrancyGuard, SignatureValidator, BaseLibEIP712 {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

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
        bytes calldata _mmSignature,
        bytes calldata _userSignature
    ) external payable override nonReentrant onlyUserProxy returns (uint256) {
        GroupedVars memory vars = _preHandleFill(_order, _mmSignature, _userSignature);
        return _settle(_order, vars, true, true);
    }

    function fillWithoutMakerSpender(
        RFQLibEIP712.Order calldata _order,
        bytes calldata _mmSignature,
        bytes calldata _userSignature
    ) external payable override nonReentrant onlyUserProxy returns (uint256) {
        GroupedVars memory vars = _preHandleFill(_order, _mmSignature, _userSignature);
        return _settle(_order, vars, true, false);
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
        GroupedVars memory _vars,
        bool _useSpenderForTaker,
        bool _useSpenderForMaker
    ) internal returns (uint256) {
        // Transfer taker asset to maker
        if (address(weth) == _order.takerAssetAddr) {
            // Deposit to WETH if taker asset is ETH
            require(msg.value == _order.takerAssetAmount, "RFQ: insufficient ETH");
            weth.deposit{ value: msg.value }();
            weth.transfer(_order.makerAddr, _order.takerAssetAmount);
        } else {
            _spendFromUserTo(_order.takerAddr, _order.takerAssetAddr, _order.makerAddr, _order.takerAssetAmount, _useSpenderForTaker);
        }

        // Transfer maker asset to taker, sub fee
        uint256 fee = _order.makerAssetAmount.mul(_order.feeFactor).div(LibConstant.BPS_MAX);
        uint256 settleAmount = _order.makerAssetAmount;
        if (fee > 0) {
            settleAmount = settleAmount.sub(fee);
        }

        // Transfer token/Eth to receiver
        if (_order.makerAssetAddr == address(weth)) {
            // Transfer from maker
            _spendFromUserTo(_order.makerAddr, _order.makerAssetAddr, address(this), settleAmount, _useSpenderForMaker);
            weth.withdraw(settleAmount);
            payable(_order.receiverAddr).transfer(settleAmount);
        } else {
            _spendFromUserTo(_order.makerAddr, _order.makerAssetAddr, _order.receiverAddr, settleAmount, _useSpenderForMaker);
        }
        // Collect fee
        if (fee > 0) {
            _spendFromUserTo(_order.makerAddr, _order.makerAssetAddr, feeCollector, fee, _useSpenderForMaker);
        }

        _emitFillOrder(_order, _vars, settleAmount);

        return settleAmount;
    }

    function _spendFromUserTo(
        address _user,
        address _tokenAddr,
        address _recipient,
        uint256 _amount,
        bool _useSpender
    ) internal {
        if (_useSpender) {
            // transferFrom by Spender
            spender.spendFromUserTo(_user, _tokenAddr, _recipient, _amount);
            return;
        }
        // transferFrom by RFQ
        uint256 balanceBefore = IERC20(_tokenAddr).balanceOf(_recipient);
        IERC20(_tokenAddr).safeTransferFrom(_user, _recipient, _amount);
        uint256 balanceAfter = IERC20(_tokenAddr).balanceOf(_recipient);
        require(balanceAfter.sub(balanceBefore) == _amount, "RFQ: ERC20 transferFrom amount mismatch");
    }

    function _preHandleFill(
        RFQLibEIP712.Order calldata _order,
        bytes calldata _mmSignature,
        bytes calldata _userSignature
    ) internal returns (GroupedVars memory) {
        // check the order deadline and fee factor
        require(_order.deadline >= block.timestamp, "RFQ: expired order");
        require(_order.feeFactor < LibConstant.BPS_MAX, "RFQ: invalid fee factor");

        GroupedVars memory vars;

        // Validate signatures
        vars.orderHash = RFQLibEIP712._getOrderHash(_order);
        require(isValidSignature(_order.makerAddr, getEIP712Hash(vars.orderHash), bytes(""), _mmSignature), "RFQ: invalid MM signature");
        vars.transactionHash = RFQLibEIP712._getTransactionHash(_order);
        require(isValidSignature(_order.takerAddr, getEIP712Hash(vars.transactionHash), bytes(""), _userSignature), "RFQ: invalid user signature");

        // Set transaction as seen, PermanentStorage would throw error if transaction already seen.
        permStorage.setRFQTransactionSeen(vars.transactionHash);

        return vars;
    }
}
