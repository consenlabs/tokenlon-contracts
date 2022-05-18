pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/ISpender.sol";
import "./interfaces/IUniswapRouterV2.sol";
import "./interfaces/ICurveFi.sol";
import "./interfaces/IAMMWrapper.sol";
import "./interfaces/IWeth.sol";
import "./interfaces/IPermanentStorage.sol";
import "./utils/AMMLibEIP712.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/SignatureValidator.sol";

contract AMMWrapper is IAMMWrapper, ReentrancyGuard, BaseLibEIP712, SignatureValidator {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Constants do not have storage slot.
    string public constant version = "5.2.0";
    uint256 internal constant MAX_UINT = 2**256 - 1;
    uint256 internal constant BPS_MAX = 10000;
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant ZERO_ADDRESS = address(0);
    address public immutable userProxy;
    IWETH public immutable weth;
    IPermanentStorage public immutable permStorage;
    address public constant UNISWAP_V2_ROUTER_02_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER_ADDRESS = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    // Below are the variables which consume storage slots.
    address public operator;
    uint256 public subsidyFactor;
    ISpender public spender;

    /* Struct and event declaration */
    // Group the local variables together to prevent
    // Compiler error: Stack too deep, try removing local variables.
    struct TxMetaData {
        string source;
        bytes32 transactionHash;
        uint256 settleAmount;
        uint256 receivedAmount;
        uint16 feeFactor;
        uint16 subsidyFactor;
    }

    struct InternalTxData {
        bool fromEth;
        bool toEth;
        address takerAssetInternalAddr;
        address makerAssetInternalAddr;
        address[] path;
        bytes makerSpecificData;
    }

    struct CurveData {
        int128 fromTokenCurveIndex;
        int128 toTokenCurveIndex;
        uint16 swapMethod;
    }

    // Operator events
    event TransferOwnership(address newOperator);
    event UpgradeSpender(address newSpender);
    event SetSubsidyFactor(uint256 newSubisdyFactor);
    event AllowTransfer(address spender);
    event DisallowTransfer(address spender);
    event DepositETH(uint256 ethBalance);

    event Swapped(
        string source,
        bytes32 indexed transactionHash,
        address indexed userAddr,
        address takerAssetAddr,
        uint256 takerAssetAmount,
        address makerAddr,
        address makerAssetAddr,
        uint256 makerAssetAmount,
        address receiverAddr,
        uint256 settleAmount,
        uint256 receivedAmount,
        uint16 feeFactor,
        uint16 subsidyFactor
    );

    receive() external payable {}

    /************************************************************
     *          Access control and ownership management          *
     *************************************************************/
    modifier onlyOperator() {
        require(operator == msg.sender, "AMMWrapper: not the operator");
        _;
    }

    modifier onlyUserProxy() {
        require(address(userProxy) == msg.sender, "AMMWrapper: not the UserProxy contract");
        _;
    }

    function transferOwnership(address _newOperator) external onlyOperator {
        require(_newOperator != address(0), "AMMWrapper: operator can not be zero address");
        operator = _newOperator;

        emit TransferOwnership(_newOperator);
    }

    /************************************************************
     *                 Internal function modifier                *
     *************************************************************/
    modifier approveTakerAsset(
        address _takerAssetInternalAddr,
        address _makerAddr,
        uint256 _takerAssetAmount
    ) {
        bool isTakerAssetETH = _isInternalAssetETH(_takerAssetInternalAddr);
        if (!isTakerAssetETH) IERC20(_takerAssetInternalAddr).safeApprove(_makerAddr, _takerAssetAmount);

        _;

        if (!isTakerAssetETH) IERC20(_takerAssetInternalAddr).safeApprove(_makerAddr, 0);
    }

    /************************************************************
     *              Constructor and init functions               *
     *************************************************************/
    constructor(
        address _operator,
        uint256 _subsidyFactor,
        address _userProxy,
        ISpender _spender,
        IPermanentStorage _permStorage,
        IWETH _weth
    ) {
        operator = _operator;
        subsidyFactor = _subsidyFactor;
        userProxy = _userProxy;
        spender = _spender;
        permStorage = _permStorage;
        weth = _weth;
    }

    /************************************************************
     *           Management functions for Operator               *
     *************************************************************/
    /**
     * @dev set new Spender
     */
    function upgradeSpender(address _newSpender) external onlyOperator {
        require(_newSpender != address(0), "AMMWrapper: spender can not be zero address");
        spender = ISpender(_newSpender);

        emit UpgradeSpender(_newSpender);
    }

    function setSubsidyFactor(uint256 _subsidyFactor) external onlyOperator {
        subsidyFactor = _subsidyFactor;

        emit SetSubsidyFactor(_subsidyFactor);
    }

    /**
     * @dev approve spender to transfer tokens from this contract. This is used to collect fee.
     */
    function setAllowance(address[] calldata _tokenList, address _spender) external override onlyOperator {
        for (uint256 i = 0; i < _tokenList.length; i++) {
            IERC20(_tokenList[i]).safeApprove(_spender, MAX_UINT);

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

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    function trade(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        uint256 _feeFactor,
        address _userAddr,
        address payable _receiverAddr,
        uint256 _salt,
        uint256 _deadline,
        bytes calldata _sig
    ) external payable override nonReentrant onlyUserProxy returns (uint256) {
        AMMLibEIP712.Order memory order = AMMLibEIP712.Order(
            _makerAddr,
            _takerAssetAddr,
            _makerAssetAddr,
            _takerAssetAmount,
            _makerAssetAmount,
            _userAddr,
            _receiverAddr,
            _salt,
            _deadline
        );
        require(order.deadline >= block.timestamp, "AMMWrapper: expired order");
        TxMetaData memory txMetaData;
        InternalTxData memory internalTxData;

        // These variables are copied straight from function parameters and
        // used to bypass stack too deep error.
        txMetaData.subsidyFactor = uint16(subsidyFactor);
        txMetaData.feeFactor = uint16(_feeFactor);
        if (!permStorage.isRelayerValid(tx.origin)) {
            txMetaData.feeFactor = (txMetaData.subsidyFactor > txMetaData.feeFactor) ? txMetaData.subsidyFactor : txMetaData.feeFactor;
            txMetaData.subsidyFactor = 0;
        }

        // Assign trade vairables
        internalTxData.fromEth = (order.takerAssetAddr == ZERO_ADDRESS || order.takerAssetAddr == ETH_ADDRESS);
        internalTxData.toEth = (order.makerAssetAddr == ZERO_ADDRESS || order.makerAssetAddr == ETH_ADDRESS);
        if (_isCurve(order.makerAddr)) {
            // PermanetStorage can recognize `ETH_ADDRESS` but not `ZERO_ADDRESS`.
            // Convert it to `ETH_ADDRESS` as passed in `order.takerAssetAddr` or `order.makerAssetAddr` might be `ZERO_ADDRESS`.
            internalTxData.takerAssetInternalAddr = internalTxData.fromEth ? ETH_ADDRESS : order.takerAssetAddr;
            internalTxData.makerAssetInternalAddr = internalTxData.toEth ? ETH_ADDRESS : order.makerAssetAddr;
        } else {
            internalTxData.takerAssetInternalAddr = internalTxData.fromEth ? address(weth) : order.takerAssetAddr;
            internalTxData.makerAssetInternalAddr = internalTxData.toEth ? address(weth) : order.makerAssetAddr;
        }

        txMetaData.transactionHash = _verify(order, _sig);

        _prepare(order, internalTxData);

        // minAmount = makerAssetAmount * (10000 - subsidyFactor) / 10000
        uint256 _minAmount = order.makerAssetAmount.mul((BPS_MAX.sub(txMetaData.subsidyFactor))).div(BPS_MAX);
        (txMetaData.source, txMetaData.receivedAmount) = _swap(order, internalTxData, _minAmount);

        // Settle
        txMetaData.settleAmount = _settle(order, txMetaData, internalTxData);

        emit Swapped(
            txMetaData.source,
            txMetaData.transactionHash,
            order.userAddr,
            order.takerAssetAddr,
            order.takerAssetAmount,
            order.makerAddr,
            order.makerAssetAddr,
            order.makerAssetAmount,
            order.receiverAddr,
            txMetaData.settleAmount,
            txMetaData.receivedAmount,
            txMetaData.feeFactor,
            txMetaData.subsidyFactor
        );

        return txMetaData.settleAmount;
    }

    /**
     * @dev internal function of `trade`.
     * Used to tell if maker is Curve.
     */
    function _isCurve(address _makerAddr) internal pure virtual returns (bool) {
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _makerAddr == SUSHISWAP_ROUTER_ADDRESS) return false;
        else return true;
    }

    /**
     * @dev internal function of `trade`.
     * Used to tell if internal asset is ETH.
     */
    function _isInternalAssetETH(address _internalAssetAddr) internal pure returns (bool) {
        if (_internalAssetAddr == ETH_ADDRESS || _internalAssetAddr == ZERO_ADDRESS) return true;
        else return false;
    }

    /**
     * @dev internal function of `trade`.
     * Get this contract's eth balance or token balance.
     */
    function _getSelfBalance(address _makerAssetInternalAddr) internal view returns (uint256) {
        if (_isInternalAssetETH(_makerAssetInternalAddr)) {
            return address(this).balance;
        } else {
            return IERC20(_makerAssetInternalAddr).balanceOf(address(this));
        }
    }

    /**
     * @dev internal function of `trade`.
     * It verifies user signature and store tx hash to prevent replay attack.
     */
    function _verify(AMMLibEIP712.Order memory _order, bytes calldata _sig) internal returns (bytes32 transactionHash) {
        // Verify user signature
        transactionHash = AMMLibEIP712._getOrderHash(_order);
        bytes32 EIP712SignDigest = getEIP712Hash(transactionHash);
        require(isValidSignature(_order.userAddr, EIP712SignDigest, bytes(""), _sig), "AMMWrapper: invalid user signature");
        // Set transaction as seen, PermanentStorage would throw error if transaction already seen.
        permStorage.setAMMTransactionSeen(transactionHash);
    }

    /**
     * @dev internal function of `trade`.
     * It executes the swap on chosen AMM.
     */
    function _prepare(AMMLibEIP712.Order memory _order, InternalTxData memory _internalTxData) internal {
        // Transfer asset from user and deposit to weth if needed
        if (_internalTxData.fromEth) {
            require(msg.value > 0, "AMMWrapper: msg.value is zero");
            require(_order.takerAssetAmount == msg.value, "AMMWrapper: msg.value doesn't match");
            // Deposit ETH to WETH if internal asset is WETH instead of ETH
            if (!_isInternalAssetETH(_internalTxData.takerAssetInternalAddr)) {
                weth.deposit{ value: msg.value }();
            }
        } else {
            // other ERC20 tokens
            spender.spendFromUser(_order.userAddr, _order.takerAssetAddr, _order.takerAssetAmount);
        }
    }

    /**
     * @dev internal function of `trade`.
     * It executes the swap on chosen AMM.
     */
    function _swap(
        AMMLibEIP712.Order memory _order,
        InternalTxData memory _internalTxData,
        uint256 _minAmount
    )
        internal
        approveTakerAsset(_internalTxData.takerAssetInternalAddr, _order.makerAddr, _order.takerAssetAmount)
        returns (string memory source, uint256 receivedAmount)
    {
        if (_order.makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _order.makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            source = (_order.makerAddr == SUSHISWAP_ROUTER_ADDRESS) ? "SushiSwap" : "Uniswap V2";
            // Sushiswap shares the same interface as Uniswap's
            receivedAmount = _tradeUniswapV2TokenToToken(
                _order.makerAddr,
                _internalTxData.takerAssetInternalAddr,
                _internalTxData.makerAssetInternalAddr,
                _order.takerAssetAmount,
                _minAmount,
                _order.deadline
            );
        } else {
            // Try to match maker with Curve pool list
            CurveData memory curveData;
            (curveData.fromTokenCurveIndex, curveData.toTokenCurveIndex, curveData.swapMethod, ) = permStorage.getCurvePoolInfo(
                _order.makerAddr,
                _internalTxData.takerAssetInternalAddr,
                _internalTxData.makerAssetInternalAddr
            );
            require(curveData.swapMethod != 0, "AMMWrapper: swap method not registered");
            if (curveData.fromTokenCurveIndex > 0 && curveData.toTokenCurveIndex > 0) {
                source = "Curve";
                // Substract index by 1 because indices stored in `permStorage` starts from 1
                curveData.fromTokenCurveIndex = curveData.fromTokenCurveIndex - 1;
                curveData.toTokenCurveIndex = curveData.toTokenCurveIndex - 1;
                // Curve does not return amount swapped so we need to record balance change instead.
                uint256 balanceBeforeTrade = _getSelfBalance(_internalTxData.makerAssetInternalAddr);
                _tradeCurveTokenToToken(
                    _order.makerAddr,
                    curveData.fromTokenCurveIndex,
                    curveData.toTokenCurveIndex,
                    _order.takerAssetAmount,
                    _minAmount,
                    curveData.swapMethod
                );
                uint256 balanceAfterTrade = _getSelfBalance(_internalTxData.makerAssetInternalAddr);
                receivedAmount = balanceAfterTrade.sub(balanceBeforeTrade);
            } else {
                revert("AMMWrapper: unsupported makerAddr");
            }
        }
    }

    /**
     * @dev internal function of `trade`.
     * It collects fee from the trade or compensates the trade based on the actual amount swapped.
     */
    function _settle(
        AMMLibEIP712.Order memory _order,
        TxMetaData memory _txMetaData,
        InternalTxData memory _internalTxData
    ) internal returns (uint256 settleAmount) {
        // Convert var type from uint16 to uint256
        uint256 _feeFactor = _txMetaData.feeFactor;
        uint256 _subsidyFactor = _txMetaData.subsidyFactor;

        if (_txMetaData.receivedAmount == _order.makerAssetAmount) {
            settleAmount = _txMetaData.receivedAmount;
        } else if (_txMetaData.receivedAmount > _order.makerAssetAmount) {
            // shouldCollectFee = ((receivedAmount - makerAssetAmount) / receivedAmount) > (feeFactor / 10000)
            bool shouldCollectFee = _txMetaData.receivedAmount.sub(_order.makerAssetAmount).mul(BPS_MAX) > _feeFactor.mul(_txMetaData.receivedAmount);
            if (shouldCollectFee) {
                // settleAmount = receivedAmount * (1 - feeFactor) / 10000
                settleAmount = _txMetaData.receivedAmount.mul(BPS_MAX.sub(_feeFactor)).div(BPS_MAX);
            } else {
                settleAmount = _order.makerAssetAmount;
            }
        } else {
            require(_subsidyFactor > 0, "AMMWrapper: this trade will not be subsidized");

            // If fee factor is smaller than subsidy factor, choose fee factor as actual subsidy factor
            // since we should subsidize less if we charge less.
            uint256 actualSubsidyFactor = (_subsidyFactor < _feeFactor) ? _subsidyFactor : _feeFactor;

            // inSubsidyRange = ((makerAssetAmount - receivedAmount) / receivedAmount) > (actualSubsidyFactor / 10000)
            bool inSubsidyRange = _order.makerAssetAmount.sub(_txMetaData.receivedAmount).mul(BPS_MAX) <= actualSubsidyFactor.mul(_txMetaData.receivedAmount);
            require(inSubsidyRange, "AMMWrapper: amount difference larger than subsidy amount");

            uint256 selfBalance = _getSelfBalance(_internalTxData.makerAssetInternalAddr);
            bool hasEnoughToSubsidize = selfBalance >= _order.makerAssetAmount;
            if (!hasEnoughToSubsidize && _isInternalAssetETH(_internalTxData.makerAssetInternalAddr)) {
                // We treat ETH and WETH the same so we have to convert WETH to ETH if ETH balance is not enough.
                uint256 amountShort = _order.makerAssetAmount.sub(selfBalance);
                if (amountShort <= weth.balanceOf(address(this))) {
                    // Withdraw the amount short from WETH
                    weth.withdraw(amountShort);
                    // Now we have enough
                    hasEnoughToSubsidize = true;
                }
            }
            require(hasEnoughToSubsidize, "AMMWrapper: not enough savings to subsidize");

            settleAmount = _order.makerAssetAmount;
        }

        // Transfer token/ETH to receiver
        if (_internalTxData.toEth) {
            // Withdraw from WETH if internal maker asset is WETH
            if (!_isInternalAssetETH(_internalTxData.makerAssetInternalAddr)) {
                weth.withdraw(settleAmount);
            }
            _order.receiverAddr.transfer(settleAmount);
        } else {
            // other ERC20 tokens
            IERC20(_order.makerAssetAddr).safeTransfer(_order.receiverAddr, settleAmount);
        }
    }

    function _tradeCurveTokenToToken(
        address _makerAddr,
        int128 i,
        int128 j,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        uint16 _swapMethod
    ) internal {
        ICurveFi curve = ICurveFi(_makerAddr);
        if (_swapMethod == 1) {
            curve.exchange{ value: msg.value }(i, j, _takerAssetAmount, _makerAssetAmount);
        } else if (_swapMethod == 2) {
            curve.exchange_underlying{ value: msg.value }(i, j, _takerAssetAmount, _makerAssetAmount);
        }
    }

    function _tradeUniswapV2TokenToToken(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        uint256 _deadline
    ) internal returns (uint256) {
        IUniswapRouterV2 router = IUniswapRouterV2(_makerAddr);
        address[] memory path = new address[](2);
        path[0] = _takerAssetAddr;
        path[1] = _makerAssetAddr;
        uint256[] memory amounts = router.swapExactTokensForTokens(_takerAssetAmount, _makerAssetAmount, path, address(this), _deadline);
        return amounts[1];
    }
}
