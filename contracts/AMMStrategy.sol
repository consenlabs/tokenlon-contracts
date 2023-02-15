// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IStrategy.sol";
import "./interfaces/IUniswapRouterV2.sol";
import "./utils/Ownable.sol";

contract AMMStrategy is IStrategy, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Emitted when entry point address is updated
    /// @param newEntryPoint The address of the new entry point
    event SetEntryPoint(address newEntryPoint);

    /// @notice Emitted after swap with AMM
    /// @param source The tag of the contract where the order is filled
    /// @param takerAssetAddr The taker assest used to swap
    /// @param takerAssetAmount The swap amount of taker asset
    /// @param makerAddr The address of maker
    /// @param makerAssetAddr The maker assest used to swap
    /// @param makerAssetAmount The swap amount of maker asset
    event Swapped(string source, address takerAssetAddr, uint256 takerAssetAmount, address makerAddr, address makerAssetAddr, uint256 makerAssetAmount);

    address public entryPoint;

    address public immutable SUSHISWAP_ROUTER_ADDRESS;
    address public immutable UNISWAP_V2_ROUTER_02_ADDRESS;
    address public immutable UNISWAP_V3_ROUTER_ADDRESS;
    address public immutable BALANCER_V2_VAULT_ADDRESS;

    constructor(
        address _owner,
        address _entryPoint,
        address _sushiwapRouter,
        address _uniswapV2Router,
        address _uniswapV3Router,
        address _balancerV2Vault
    ) Ownable(_owner) {
        entryPoint = _entryPoint;
        SUSHISWAP_ROUTER_ADDRESS = _sushiwapRouter;
        UNISWAP_V2_ROUTER_02_ADDRESS = _uniswapV2Router;
        UNISWAP_V3_ROUTER_ADDRESS = _uniswapV3Router;
        BALANCER_V2_VAULT_ADDRESS = _balancerV2Vault;
    }

    modifier onlyEntryPoint() {
        require(msg.sender == entryPoint, "only entry point");
        _;
    }

    modifier approveTakerAsset(
        address _takerAssetAddr,
        address _makerAddr,
        uint256 _takerAssetAmount
    ) {
        IERC20(_takerAssetAddr).safeApprove(_makerAddr, _takerAssetAmount);
        _;
        IERC20(_takerAssetAddr).safeApprove(_makerAddr, 0);
    }

    function setEntryPoint(address _newEntryPoint) external onlyOwner {
        entryPoint = _newEntryPoint;
        emit SetEntryPoint(_newEntryPoint);
    }

    // only work for erc-20
    function executeStrategy(
        address srcToken,
        uint256 inputAmount,
        bytes calldata data
    ) external override nonReentrant onlyEntryPoint {
        (address makerAddr, address makerAssetAddr, bytes memory makerSpecificData, address[] memory path, uint256 deadline) = abi.decode(
            data,
            (address, address, bytes, address[], uint256)
        );
        (string memory source, uint256 receivedAmount) = _swap(srcToken, inputAmount, makerAddr, makerAssetAddr, makerSpecificData, path, deadline);
        IERC20(makerAssetAddr).safeTransfer(entryPoint, receivedAmount);
        // should emit event?
        // which parameter should be indexed?
        emit Swapped(source, srcToken, inputAmount, makerAddr, makerAssetAddr, receivedAmount);
    }

    function _swap(
        address _takerAssetAddr,
        uint256 _takerAssetAmount,
        address _makerAddr,
        address _makerAssetAddr,
        // solhint-disable-next-line
        bytes memory _makerSpecificData,
        address[] memory _path,
        uint256 _deadline
    ) internal approveTakerAsset(_takerAssetAddr, _makerAddr, _takerAssetAmount) returns (string memory source, uint256 receivedAmount) {
        if (_makerAddr == UNISWAP_V2_ROUTER_02_ADDRESS || _makerAddr == SUSHISWAP_ROUTER_ADDRESS) {
            source = (_makerAddr == SUSHISWAP_ROUTER_ADDRESS) ? "SushiSwap" : "Uniswap V2";
            receivedAmount = _tradeUniswapV2TokenToToken(_makerAddr, _takerAssetAddr, _makerAssetAddr, _takerAssetAmount, _deadline, _path);
        }
    }

    function _tradeUniswapV2TokenToToken(
        address _makerAddr,
        address _takerAssetAddr,
        address _makerAssetAddr,
        uint256 _takerAssetAmount,
        uint256 _deadline,
        address[] memory _path
    ) internal returns (uint256) {
        IUniswapRouterV2 router = IUniswapRouterV2(_makerAddr);
        if (_path.length == 0) {
            _path = new address[](2);
            _path[0] = _takerAssetAddr;
            _path[1] = _makerAssetAddr;
        } else {
            _validateAMMPath(_path, _takerAssetAddr, _makerAssetAddr);
        }
        // min received token should be assured by entryPoint
        uint256[] memory amounts = router.swapExactTokensForTokens(_takerAssetAmount, 0, _path, address(this), _deadline);
        return amounts[amounts.length - 1];
    }

    function _validateAMMPath(
        address[] memory _path,
        address _takerAssetAddr,
        address _makerAssetAddr
    ) internal pure {
        require(_path.length >= 2, "AMMStrategy: path length must be at least two");
        require(_path[0] == _takerAssetAddr, "AMMStrategy: first element of path must match taker asset");
        require(_path[_path.length - 1] == _makerAssetAddr, "AMMStrategy: last element of path must match maker asset");
    }
}
