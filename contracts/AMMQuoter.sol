pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IUniswapExchange.sol";
import "./interfaces/IUniswapFactory.sol";
import "./interfaces/IUniswapRouterV2.sol";
import "./interfaces/ICurveFi.sol";
import "./interfaces/IWeth.sol";
import "./interfaces/IPermanentStorage.sol";

contract AMMQuoter {
    using SafeMath for uint256;
    /* Constants */
    string public constant version = "5.1.0";
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant ZERO_ADDRESS = address(0);
    address public constant UNISWAP_V2_ROUTER_02_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER_ADDRESS = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public immutable weth;
    IPermanentStorage public immutable permStorage;

    event CurveTokenAdded(address indexed makerAddress, address indexed assetAddress, int128 index);

    constructor(IPermanentStorage _permStorage, address _weth) public {
        permStorage = _permStorage;
        weth = _weth;
    }

    function isETH(address assetAddress) public pure returns (bool) {
        return (assetAddress == ZERO_ADDRESS || assetAddress == ETH_ADDRESS);
    }

    function getMakerOutAmount(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount
    ) public view returns (uint256) {
        uint256 makerAssetAmount;
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            IUniswapRouterV2 router = IUniswapRouterV2(_makerAddr);
            address[] memory path = new address[](2);
            if (isETH(_takerAssetAddr)) {
                path[0] = weth;
                path[1] = _makerAssetAddr;
            } else if (isETH(_makerAssetAddr)) {
                path[0] = _takerAssetAddr;
                path[1] = weth;
            } else {
                path[0] = _takerAssetAddr;
                path[1] = _makerAssetAddr;
            }
            uint256[] memory amounts = router.getAmountsOut(_takerAssetAmount, path);
            makerAssetAmount = amounts[1];
        } else {
            address curveTakerIntenalAsset = isETH(_takerAssetAddr) ? ETH_ADDRESS : _takerAssetAddr;
            address curveMakerIntenalAsset = isETH(_makerAssetAddr) ? ETH_ADDRESS : _makerAssetAddr;
            (int128 fromTokenCurveIndex, int128 toTokenCurveIndex, uint16 swapMethod, ) = permStorage.getCurvePoolInfo(
                _makerAddr,
                curveTakerIntenalAsset,
                curveMakerIntenalAsset
            );
            if (fromTokenCurveIndex > 0 && toTokenCurveIndex > 0) {
                require(swapMethod != 0, "AMMQuoter: swap method not registered");
                // Substract index by 1 because indices stored in `permStorage` starts from 1
                fromTokenCurveIndex = fromTokenCurveIndex - 1;
                toTokenCurveIndex = toTokenCurveIndex - 1;
                ICurveFi curve = ICurveFi(_makerAddr);
                if (swapMethod == 1) {
                    makerAssetAmount = curve.get_dy(fromTokenCurveIndex, toTokenCurveIndex, _takerAssetAmount).sub(1);
                } else if (swapMethod == 2) {
                    makerAssetAmount = curve.get_dy_underlying(fromTokenCurveIndex, toTokenCurveIndex, _takerAssetAmount).sub(1);
                }
            } else {
                revert("AMMQuoter: Unsupported makerAddr");
            }
        }
        return makerAssetAmount;
    }

    function getBestOutAmount(
        address[] calldata _makerAddresses,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount
    ) external view returns (address bestMaker, uint256 bestAmount) {
        bestAmount = 0;
        uint256 poolLength = _makerAddresses.length;
        for (uint256 i = 0; i < poolLength; i++) {
            address makerAddress = _makerAddresses[i];
            uint256 makerAssetAmount = getMakerOutAmount(makerAddress, _takerAssetAddr, _makerAssetAddr, _takerAssetAmount);
            if (makerAssetAmount > bestAmount) {
                bestAmount = makerAssetAmount;
                bestMaker = makerAddress;
            }
        }
        return (bestMaker, bestAmount);
    }

    function getTakerInAmount(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _makerAssetAmount
    ) public view returns (uint256) {
        uint256 takerAssetAmount;
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            IUniswapRouterV2 router = IUniswapRouterV2(_makerAddr);
            address[] memory path = new address[](2);
            if (isETH(_takerAssetAddr)) {
                path[0] = weth;
                path[1] = _makerAssetAddr;
            } else if (isETH(_makerAssetAddr)) {
                path[0] = _takerAssetAddr;
                path[1] = weth;
            } else {
                path[0] = _takerAssetAddr;
                path[1] = _makerAssetAddr;
            }
            uint256[] memory amounts = router.getAmountsIn(_makerAssetAmount, path);
            takerAssetAmount = amounts[0];
        } else {
            address curveTakerIntenalAsset = isETH(_takerAssetAddr) ? ETH_ADDRESS : _takerAssetAddr;
            address curveMakerIntenalAsset = isETH(_makerAssetAddr) ? ETH_ADDRESS : _makerAssetAddr;
            (int128 fromTokenCurveIndex, int128 toTokenCurveIndex, uint16 swapMethod, bool supportGetDx) = permStorage.getCurvePoolInfo(
                _makerAddr,
                curveTakerIntenalAsset,
                curveMakerIntenalAsset
            );
            if (fromTokenCurveIndex > 0 && toTokenCurveIndex > 0) {
                require(swapMethod != 0, "AMMQuoter: swap method not registered");
                // Substract index by 1 because indices stored in `permStorage` starts from 1
                fromTokenCurveIndex = fromTokenCurveIndex - 1;
                toTokenCurveIndex = toTokenCurveIndex - 1;
                ICurveFi curve = ICurveFi(_makerAddr);
                if (supportGetDx) {
                    if (swapMethod == 1) {
                        takerAssetAmount = curve.get_dx(fromTokenCurveIndex, toTokenCurveIndex, _makerAssetAmount);
                    } else if (swapMethod == 2) {
                        takerAssetAmount = curve.get_dx_underlying(fromTokenCurveIndex, toTokenCurveIndex, _makerAssetAmount);
                    }
                } else {
                    if (swapMethod == 1) {
                        // does not support get_dx_underlying, try to get an estimated rate here
                        takerAssetAmount = curve.get_dy(toTokenCurveIndex, fromTokenCurveIndex, _makerAssetAmount);
                    } else if (swapMethod == 2) {
                        takerAssetAmount = curve.get_dy_underlying(toTokenCurveIndex, fromTokenCurveIndex, _makerAssetAmount);
                    }
                }
            } else {
                revert("AMMQuoter: Unsupported makerAddr");
            }
        }
        return takerAssetAmount;
    }

    function getBestInAmount(
        address[] calldata _makerAddresses,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _makerAssetAmount
    ) external view returns (address bestMaker, uint256 bestAmount) {
        bestAmount = 2**256 - 1;
        uint256 poolLength = _makerAddresses.length;
        for (uint256 i = 0; i < poolLength; i++) {
            address makerAddress = _makerAddresses[i];
            uint256 takerAssetAmount = getTakerInAmount(makerAddress, _takerAssetAddr, _makerAssetAddr, _makerAssetAmount);
            if (takerAssetAmount < bestAmount) {
                bestAmount = takerAssetAmount;
                bestMaker = makerAddress;
            }
        }
        return (bestMaker, bestAmount);
    }
}
