// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/ISpender.sol";
import "./interfaces/IUniswapRouterV2.sol";
import "./interfaces/ICurveFi.sol";
import "./interfaces/ICurveFiV2.sol";
import "./interfaces/IAMMWrapper.sol";
import "./interfaces/IWeth.sol";
import "./interfaces/IPermanentStorage.sol";
import "./utils/AMMLibEIP712.sol";
import "./utils/BaseLibEIP712.sol";
import "./utils/LibConstant.sol";
import "./utils/SignatureValidator.sol";

contract AMMWrapper is IAMMWrapper, ReentrancyGuard, BaseLibEIP712, SignatureValidator {
    using SafeMath for uint16;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Constants do not have storage slot.
    address public immutable userProxy;
    IWETH public immutable weth;
    IPermanentStorage public immutable permStorage;
    address public immutable UNISWAP_V2_ROUTER_02_ADDRESS;
    address public immutable SUSHISWAP_ROUTER_ADDRESS;

    // Below are the variables which consume storage slots.
    address public operator;
    uint16 public defaultFeeFactor;
    ISpender public spender;
    address public feeCollector;

    /* Struct declaration */

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
        uint16 _defaultFeeFactor,
        address _userProxy,
        ISpender _spender,
        IPermanentStorage _permStorage,
        IWETH _weth,
        address _uniswapV2Router,
        address _sushiwapRouter,
        address _feeCollector
    ) {
        operator = _operator;
        defaultFeeFactor = _defaultFeeFactor;
        userProxy = _userProxy;
        spender = _spender;
        permStorage = _permStorage;
        weth = _weth;
        UNISWAP_V2_ROUTER_02_ADDRESS = _uniswapV2Router;
        SUSHISWAP_ROUTER_ADDRESS = _sushiwapRouter;
        feeCollector = _feeCollector;
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

    /**
     * @dev set default fee factor
     */
    function setDefaultFeeFactor(uint16 _defaultFeeFactor) external onlyOperator {
        defaultFeeFactor = _defaultFeeFactor;

        emit SetDefaultFeeFactor(defaultFeeFactor);
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
        require(_newFeeCollector != address(0), "AMMWrapper: fee collector can not be zero address");
        feeCollector = _newFeeCollector;

        emit SetFeeCollector(_newFeeCollector);
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

        // These variables are copied straight from function parameters and
        // used to bypass stack too deep error.
        TxMetaData memory txMetaData;
        InternalTxData memory internalTxData;
        txMetaData.feeFactor = uint16(_feeFactor);
        txMetaData.relayed = permStorage.isRelayerValid(tx.origin);
        if (!txMetaData.relayed) {
            // overwrite feeFactor with defaultFeeFactor if not from valid relayer
            txMetaData.feeFactor = defaultFeeFactor;
        }

        // Assign trade vairables
        internalTxData.fromEth = (order.takerAssetAddr == LibConstant.ZERO_ADDRESS || order.takerAssetAddr == LibConstant.ETH_ADDRESS);
        internalTxData.toEth = (order.makerAssetAddr == LibConstant.ZERO_ADDRESS || order.makerAssetAddr == LibConstant.ETH_ADDRESS);
        if (_isCurve(order.makerAddr)) {
            // PermanetStorage can recognize `ETH_ADDRESS` but not `ZERO_ADDRESS`.
            // Convert it to `ETH_ADDRESS` as passed in `order.takerAssetAddr` or `order.makerAssetAddr` might be `ZERO_ADDRESS`.
            internalTxData.takerAssetInternalAddr = internalTxData.fromEth ? LibConstant.ETH_ADDRESS : order.takerAssetAddr;
            internalTxData.makerAssetInternalAddr = internalTxData.toEth ? LibConstant.ETH_ADDRESS : order.makerAssetAddr;
        } else {
            internalTxData.takerAssetInternalAddr = internalTxData.fromEth ? address(weth) : order.takerAssetAddr;
            internalTxData.makerAssetInternalAddr = internalTxData.toEth ? address(weth) : order.makerAssetAddr;
        }

        txMetaData.transactionHash = _verify(order, _sig);

        _prepare(order, internalTxData);

        {
            // Set min amount for swap = _order.makerAssetAmount * (10000 / (10000 - feeFactor))
            uint256 swapMinOutAmount = order.makerAssetAmount.mul(LibConstant.BPS_MAX).div(LibConstant.BPS_MAX.sub(txMetaData.feeFactor));
            (txMetaData.source, txMetaData.receivedAmount) = _swap(order, internalTxData, swapMinOutAmount);

            // Settle
            // Calculate fee using actually received from swap
            uint256 actualFee = txMetaData.receivedAmount.mul(txMetaData.feeFactor).div(LibConstant.BPS_MAX);
            txMetaData.settleAmount = txMetaData.receivedAmount.sub(actualFee);
            require(txMetaData.settleAmount >= order.makerAssetAmount, "AMMWrapper: insufficient maker output");
            _settle(order, internalTxData, txMetaData.settleAmount, actualFee);
        }

        emitSwappedEvent(order, txMetaData);
        return txMetaData.settleAmount;
    }

    /**
     * @dev internal function of `trade`.
     * Used to tell if maker is Curve.
     */
    function _isCurve(address _makerAddr) internal view virtual returns (bool) {
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _makerAddr == SUSHISWAP_ROUTER_ADDRESS) return false;
        else return true;
    }

    /**
     * @dev internal function of `trade`.
     * Used to tell if internal asset is ETH.
     */
    function _isInternalAssetETH(address _internalAssetAddr) internal pure returns (bool) {
        if (_internalAssetAddr == LibConstant.ETH_ADDRESS || _internalAssetAddr == LibConstant.ZERO_ADDRESS) return true;
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
                    1, // AMMWrapper call only interact with curveV1
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
     * It transfer assets to receiver specified in order.
     */
    function _settle(
        AMMLibEIP712.Order memory _order,
        InternalTxData memory _internalTxData,
        uint256 _settleAmount,
        uint256 _feeAmount
    ) internal {
        // Transfer token/ETH to receiver
        if (_internalTxData.toEth) {
            // Withdraw from WETH if internal maker asset is WETH
            if (!_isInternalAssetETH(_internalTxData.makerAssetInternalAddr)) {
                weth.withdraw(_settleAmount);
            }
            _order.receiverAddr.transfer(_settleAmount);
        } else {
            // other ERC20 tokens
            IERC20(_order.makerAssetAddr).safeTransfer(_order.receiverAddr, _settleAmount);
        }
        // Collect fee
        if (_feeAmount > 0) {
            if (_internalTxData.toEth) {
                // Transfer WETH directly if internal maker asset is WETH
                if (!_isInternalAssetETH(_internalTxData.makerAssetInternalAddr)) {
                    weth.transfer(feeCollector, _feeAmount);
                } else {
                    payable(feeCollector).transfer(_feeAmount);
                }
            } else {
                // other ERC20 tokens
                IERC20(_order.makerAssetAddr).safeTransfer(feeCollector, _feeAmount);
            }
        }
    }

    function _tradeCurveTokenToToken(
        address _makerAddr,
        uint8 _version,
        int128 i,
        int128 j,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        uint16 _swapMethod
    ) internal {
        if (_version == 1) {
            ICurveFi curve = ICurveFi(_makerAddr);
            if (_swapMethod == 1) {
                curve.exchange{ value: msg.value }(i, j, _takerAssetAmount, _makerAssetAmount);
                return;
            } else if (_swapMethod == 2) {
                curve.exchange_underlying{ value: msg.value }(i, j, _takerAssetAmount, _makerAssetAmount);
                return;
            }
            revert("AMMWrapper: Invalid swapMethod for CurveV1");
        } else if (_version == 2) {
            ICurveFiV2 curve = ICurveFiV2(_makerAddr);
            require(_swapMethod == 1, "AMMWrapper: Curve v2 no underlying");
            curve.exchange{ value: msg.value }(uint256(i), uint256(j), _takerAssetAmount, _makerAssetAmount, true);
            return;
        }
        revert("AMMWrapper: Invalid Curve version");
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

    function emitSwappedEvent(AMMLibEIP712.Order memory _order, TxMetaData memory _txMetaData) internal {
        emit Swapped(
            _txMetaData.source,
            _txMetaData.transactionHash,
            _order.userAddr,
            _txMetaData.relayed,
            _order.takerAssetAddr,
            _order.takerAssetAmount,
            _order.makerAddr,
            _order.makerAssetAddr,
            _order.makerAssetAmount,
            _order.receiverAddr,
            _txMetaData.settleAmount,
            _txMetaData.feeFactor
        );
    }
}
