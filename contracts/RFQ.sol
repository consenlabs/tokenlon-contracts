// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/ISpender.sol";
import "./interfaces/IWeth.sol";
import "./interfaces/IRFQ.sol";
import "./interfaces/IPermanentStorage.sol";
import "./interfaces/IERC1271Wallet.sol";
import "./utils/RFQLibEIP712.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/SignatureValidator.sol";
import "./utils/LibConstant.sol";

contract RFQ is IRFQ, ReentrancyGuard, SignatureValidator, BaseLibEIP712 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    // Constants do not have storage slot.
    string public constant SOURCE = "RFQ v1";
    address public immutable userProxy;
    IPermanentStorage public immutable permStorage;
    IWETH public immutable weth;

    // Below are the variables which consume storage slots.
    address public operator;
    ISpender public spender;
    address public feeCollector;

    struct GroupedVars {
        bytes32 orderHash;
        bytes32 transactionHash;
    }

    // Operator events
    event TransferOwnership(address newOperator);
    event UpgradeSpender(address newSpender);
    event AllowTransfer(address spender);
    event DisallowTransfer(address spender);
    event DepositETH(uint256 ethBalance);
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
     *          Access control and ownership management          *
     *************************************************************/
    modifier onlyOperator() {
        require(operator == msg.sender, "RFQ: not operator");
        _;
    }

    modifier onlyUserProxy() {
        require(address(userProxy) == msg.sender, "RFQ: not the UserProxy contract");
        _;
    }

    function transferOwnership(address _newOperator) external onlyOperator {
        require(_newOperator != address(0), "RFQ: operator can not be zero address");
        operator = _newOperator;

        emit TransferOwnership(_newOperator);
    }

    /************************************************************
     *              Constructor and init functions               *
     *************************************************************/
    constructor(
        address _operator,
        address _userProxy,
        ISpender _spender,
        IPermanentStorage _permStorage,
        IWETH _weth,
        address _feeCollector
    ) {
        operator = _operator;
        userProxy = _userProxy;
        spender = _spender;
        permStorage = _permStorage;
        weth = _weth;
        feeCollector = _feeCollector;
    }

    /************************************************************
     *           Management functions for Operator               *
     *************************************************************/
    /**
     * @dev set new Spender
     */
    function upgradeSpender(address _newSpender) external onlyOperator {
        require(_newSpender != address(0), "RFQ: spender can not be zero address");
        spender = ISpender(_newSpender);

        emit UpgradeSpender(_newSpender);
    }

    /**
     * @dev approve spender to transfer tokens from this contract. This is used to collect fee.
     */
    function setAllowance(address[] calldata _tokenList, address _spender) external override onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, LibConstant.MAX_UINT);

            emit AllowTransfer(_spender);
        }
    }

    function closeAllowance(address[] calldata _tokenList, address _spender) external override onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, 0);

            emit DisallowTransfer(_spender);
        }
    }

    /**
     * @dev convert collected ETH to WETH
     */
    function depositETH() external onlyOperator {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            weth.deposit{ value: balance }();

            emit DepositETH(balance);
        }
    }

    /**
     * @dev set fee collector
     */
    function setFeeCollector(address _newFeeCollector) external onlyOperator {
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

        return _settle(_order, vars);
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
    function _settle(RFQLibEIP712.Order memory _order, GroupedVars memory _vars) internal returns (uint256) {
        // Transfer taker asset to maker
        if (address(weth) == _order.takerAssetAddr) {
            // Deposit to WETH if taker asset is ETH
            require(msg.value == _order.takerAssetAmount, "RFQ: insufficient ETH");
            weth.deposit{ value: msg.value }();
            weth.transfer(_order.makerAddr, _order.takerAssetAmount);
        } else {
            spender.spendFromUserTo(_order.takerAddr, _order.takerAssetAddr, _order.makerAddr, _order.takerAssetAmount);
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
            spender.spendFromUser(_order.makerAddr, _order.makerAssetAddr, settleAmount);
            weth.withdraw(settleAmount);
            payable(_order.receiverAddr).transfer(settleAmount);
        } else {
            spender.spendFromUserTo(_order.makerAddr, _order.makerAssetAddr, _order.receiverAddr, settleAmount);
        }
        // Collect fee
        if (fee > 0) {
            spender.spendFromUserTo(_order.makerAddr, _order.makerAssetAddr, feeCollector, fee);
        }

        _emitFillOrder(_order, _vars, settleAmount);

        return settleAmount;
    }
}
