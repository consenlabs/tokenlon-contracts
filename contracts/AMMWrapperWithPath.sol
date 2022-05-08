pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./AMMWrapper.sol";
import "./interfaces/ISpender.sol";
import "./interfaces/IUniswapRouterV2.sol";
import "./interfaces/IUniswapV3SwapRouter.sol";
import "./interfaces/IPermanentStorage.sol";
import "./utils/UniswapV3PathLib.sol";

contract AMMWrapperWithPath is AMMWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Path for bytes;
    using LibBytes for bytes;

    // Constants do not have storage slot.
    address public constant UNISWAP_V3_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    event Swapped(TxMetaData, Order order);

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
    ) public AMMWrapper(_operator, _subsidyFactor, _userProxy, _spender, _permStorage, _weth) {}

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    function trade(
        Order memory _order,
        uint256 _feeFactor,
        bytes calldata _sig,
        bytes calldata _makerSpecificData,
        address[] calldata _path
    ) external payable nonReentrant onlyUserProxy returns (uint256) {
        require(_order.deadline >= block.timestamp, "AMMWrapper: expired order");
        TxMetaData memory txMetaData;
        InternalTxData memory internalTxData;

        // These variables are copied straight from function parameters and
        // used to bypass stack too deep error.
        txMetaData.subsidyFactor = uint16(subsidyFactor);
        txMetaData.feeFactor = uint16(_feeFactor);
        internalTxData.makerSpecificData = _makerSpecificData;
        internalTxData.path = _path;
        if (!permStorage.isRelayerValid(tx.origin)) {
            txMetaData.feeFactor = (txMetaData.subsidyFactor > txMetaData.feeFactor) ? txMetaData.subsidyFactor : txMetaData.feeFactor;
            txMetaData.subsidyFactor = 0;
        }

        // Assign trade vairables
        internalTxData.fromEth = (_order.takerAssetAddr == ZERO_ADDRESS || _order.takerAssetAddr == ETH_ADDRESS);
        internalTxData.toEth = (_order.makerAssetAddr == ZERO_ADDRESS || _order.makerAssetAddr == ETH_ADDRESS);
        if (_isCurve(_order.makerAddr)) {
            // PermanetStorage can recognize `ETH_ADDRESS` but not `ZERO_ADDRESS`.
            // Convert it to `ETH_ADDRESS` as passed in `_order.takerAssetAddr` or `_order.makerAssetAddr` might be `ZERO_ADDRESS`.
            internalTxData.takerAssetInternalAddr = internalTxData.fromEth ? ETH_ADDRESS : _order.takerAssetAddr;
            internalTxData.makerAssetInternalAddr = internalTxData.toEth ? ETH_ADDRESS : _order.makerAssetAddr;
        } else {
            internalTxData.takerAssetInternalAddr = internalTxData.fromEth ? address(weth) : _order.takerAssetAddr;
            internalTxData.makerAssetInternalAddr = internalTxData.toEth ? address(weth) : _order.makerAssetAddr;
        }

        txMetaData.transactionHash = _verify(_order, _sig);

        _prepare(_order, internalTxData);

        (txMetaData.source, txMetaData.receivedAmount) = _swapWithPath(_order, txMetaData, internalTxData);

        // Settle
        txMetaData.settleAmount = _settle(_order, txMetaData, internalTxData);

        emit Swapped(txMetaData, _order);

        return txMetaData.settleAmount;
    }

    /**
     * @dev internal function of `trade`.
     * Used to tell if maker is Curve.
     */
    function _isCurve(address _makerAddr) internal pure override returns (bool) {
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _makerAddr == UNISWAP_V3_ROUTER_ADDRESS || _makerAddr == SUSHISWAP_ROUTER_ADDRESS) return false;
        else return true;
    }

    /**
     * @dev internal function of `trade`.
     * It executes the swap on chosen AMM.
     */
    function _swapWithPath(
        Order memory _order,
        TxMetaData memory _txMetaData,
        InternalTxData memory _internalTxData
    ) internal approveTakerAsset(_internalTxData.takerAssetInternalAddr, _order.makerAddr) returns (string memory source, uint256 receivedAmount) {
        // Swap
        // minAmount = makerAssetAmount * (10000 - subsidyFactor) / 10000
        uint256 minAmount = _order.makerAssetAmount.mul((BPS_MAX.sub(_txMetaData.subsidyFactor))).div(BPS_MAX);

        if (_order.makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _order.makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            source = (_order.makerAddr == SUSHISWAP_ROUTER_ADDRESS) ? "SushiSwap" : "Uniswap V2";
            // Sushiswap shares the same interface as Uniswap's
            receivedAmount = _tradeUniswapV2TokenToToken(
                _order.makerAddr,
                _internalTxData.takerAssetInternalAddr,
                _internalTxData.makerAssetInternalAddr,
                _order.takerAssetAmount,
                minAmount,
                _order.deadline,
                _internalTxData.path
            );
        } else if (_order.makerAddr == UNISWAP_V3_ROUTER_ADDRESS) {
            source = "Uniswap V3";
            receivedAmount = _tradeUniswapV3TokenToToken(
                _order.makerAddr,
                _internalTxData.takerAssetInternalAddr,
                _internalTxData.makerAssetInternalAddr,
                _order.deadline,
                _order.takerAssetAmount,
                minAmount,
                _internalTxData.makerSpecificData
            );
        } else {
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
                    minAmount,
                    curveData.swapMethod
                );
                uint256 balanceAfterTrade = _getSelfBalance(_internalTxData.makerAssetInternalAddr);
                receivedAmount = balanceAfterTrade.sub(balanceBeforeTrade);
            } else {
                revert("AMMWrapper: unsupported makerAddr");
            }
        }
    }

    function _tradeUniswapV2TokenToToken(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        uint256 _deadline,
        address[] memory _path
    ) internal returns (uint256) {
        IUniswapRouterV2 router = IUniswapRouterV2(_makerAddr);
        if (_path.length == 0) {
            _path = new address[](2);
            _path[0] = _takerAssetAddr;
            _path[1] = _makerAssetAddr;
        } else {
            require(_path.length >= 2, "AMMWrapper: path length must be at least two");
            require(_path[0] == _takerAssetAddr, "AMMWrapper: first element of path must match taker asset");
            require(_path[_path.length - 1] == _makerAssetAddr, "AMMWrapper: last element of path must match maker asset");
        }
        uint256[] memory amounts = router.swapExactTokensForTokens(_takerAssetAmount, _makerAssetAmount, _path, address(this), _deadline);
        return amounts[amounts.length - 1];
    }

    function _validateUniswapV3Path(
        bytes memory _path,
        address _takerAssetAddr,
        address _makerAssetAddr
    ) internal {
        (address tokenA, address tokenB, ) = _path.decodeFirstPool();

        if (_path.hasMultiplePools()) {
            _path = _path.skipToken();
            while (_path.hasMultiplePools()) {
                _path = _path.skipToken();
            }
            (, tokenB, ) = _path.decodeFirstPool();
        }

        require(tokenA == _takerAssetAddr, "AMMWrapper: first element of path must match taker asset");
        require(tokenB == _makerAssetAddr, "AMMWrapper: last element of path must match maker asset");
    }

    function _tradeUniswapV3TokenToToken(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _deadline,
        uint256 _takerAssetAmount,
        uint256 _makerAssetAmount,
        bytes memory _makerSpecificData
    ) internal returns (uint256 amountOut) {
        ISwapRouter router = ISwapRouter(_makerAddr);
        // swapType:
        // 1: exactInputSingle, 2: exactInput
        uint8 swapType = uint8(uint256(_makerSpecificData.readBytes32(0)));

        if (swapType == 1) {
            (, uint24 poolFee) = abi.decode(_makerSpecificData, (uint8, uint24));
            ISwapRouter.ExactInputSingleParams memory exactInputSingleParams;
            exactInputSingleParams.tokenIn = _takerAssetAddr;
            exactInputSingleParams.tokenOut = _makerAssetAddr;
            exactInputSingleParams.fee = poolFee;
            exactInputSingleParams.recipient = address(this);
            exactInputSingleParams.deadline = _deadline;
            exactInputSingleParams.amountIn = _takerAssetAmount;
            exactInputSingleParams.amountOutMinimum = _makerAssetAmount;
            exactInputSingleParams.sqrtPriceLimitX96 = 0;

            amountOut = router.exactInputSingle(exactInputSingleParams);
        } else if (swapType == 2) {
            (, bytes memory path) = abi.decode(_makerSpecificData, (uint8, bytes));
            _validateUniswapV3Path(path, _takerAssetAddr, _makerAssetAddr);
            ISwapRouter.ExactInputParams memory exactInputParams;
            exactInputParams.path = path;
            exactInputParams.recipient = address(this);
            exactInputParams.deadline = _deadline;
            exactInputParams.amountIn = _takerAssetAmount;
            exactInputParams.amountOutMinimum = _makerAssetAmount;

            amountOut = router.exactInput(exactInputParams);
        } else {
            revert("AMMWrapper: unsupported UniswapV3 swap type");
        }
    }
}
