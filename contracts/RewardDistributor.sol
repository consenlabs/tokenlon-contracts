// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "contracts/interfaces/IUniswapRouterV2.sol";
import "contracts/interfaces/IUniswapV3SwapRouter.sol";
import "contracts/interfaces/ILon.sol";
import "contracts/utils/LibBytes.sol";
import "contracts/Ownable.sol";
import "contracts/utils/UniswapV3PathLib.sol";

contract RewardDistributor is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using LibBytes for bytes;
    using Path for bytes;

    // Constants do not have storage slot.
    uint256 private constant MAX_UINT = 2**256 - 1;
    uint8 private constant UNISWAP_V2_INDEX = 0;
    uint8 private constant SUSHISWAP_INDEX = 1;
    uint8 private constant UNISWAP_V3_INDEX = 2;
    address public immutable UNISWAP_V2_ROUTER_02_ADDRESS;
    address public immutable UNISWAP_V3_ROUTER_ADDRESS;
    address public immutable SUSHISWAP_ROUTER_ADDRESS;
    address public immutable LON_TOKEN_ADDR;
    uint32 public immutable MIN_BUYBACK_INTERVAL;

    // Below are the variables which consume storage slots.
    uint32 public buybackInterval;
    uint8 public miningFactor;
    uint8 public numStrategyAddr;
    uint8 public numExchangeAddr;

    mapping(address => bool) public isOperator;
    address public treasury;
    address public lonStaking;
    address public miningTreasury;
    address public feeTokenRecipient;

    mapping(uint256 => address) public strategyAddrs;
    mapping(address => FeeToken) public feeTokens;

    /* Struct and event declaration */
    struct FeeToken {
        uint8 LFactor; // Percentage of fee token reserved for feeTokenRecipient
        uint8 RFactor; // Percentage of buyback-ed lon token for treasury
        uint32 lastTimeBuyback;
        bool enable;
        uint256 minBuy;
        uint256 maxBuy;
        bytes encodedAMMRoute;
    }

    struct ConstructorParams {
        address lonTokenAddr;
        address sushiRouterAddr;
        address uniswapV2RouterAddr;
        address uniswapV3RouterAddr;
        address owner;
        address operator;
        uint32 minBuyBackInterval;
        uint32 buyBackInterval;
        uint8 miningFactor;
        address treasury;
        address lonStaking;
        address miningTreasury;
        address feeTokenRecipient;
    }

    // Owner events
    event SetOperator(address operator, bool enable);
    event SetMiningFactor(uint8 miningFactor);
    event SetTreasury(address treasury);
    event SetLonStaking(address lonStaking);
    event SetMiningTreasury(address miningTreasury);
    event SetFeeTokenRecipient(address feeTokenRecipient);
    // Operator events
    event SetBuybackInterval(uint256 interval);
    event SetStrategy(uint256 index, address strategy);
    event EnableFeeToken(address feeToken, bool enable);
    event SetFeeToken(address feeToken, bytes encodedAMMRoute, uint256 LFactor, uint256 RFactor, uint256 minBuy, uint256 maxBuy);
    event SetFeeTokenFailure(address feeToken, string reason, bytes lowLevelData);
    // Main events
    event BuyBack(address feeToken, uint256 feeTokenAmount, uint256 swappedLonAmount, uint256 LFactor, uint256 RFactor, uint256 minBuy, uint256 maxBuy);
    event BuyBackFailure(address feeToken, uint256 feeTokenAmount, string reason, bytes lowLevelData);
    event DistributeLon(uint256 treasuryAmount, uint256 lonStakingAmount);
    event MintLon(uint256 mintedAmount);
    event Recovered(address token, uint256 amount);

    /************************************************************
     *                      Access control                       *
     *************************************************************/
    modifier only_Operator_or_Owner() {
        require(_isAuthorized(msg.sender), "only operator or owner can call");
        _;
    }

    modifier only_Owner_or_Operator_or_Self() {
        if (msg.sender != address(this)) {
            require(_isAuthorized(msg.sender), "only operator or owner can call");
        }
        _;
    }

    modifier only_EOA() {
        require((msg.sender == tx.origin), "only EOA can call");
        _;
    }

    modifier only_EOA_or_Self() {
        if (msg.sender != address(this)) {
            require((msg.sender == tx.origin), "only EOA can call");
        }
        _;
    }

    /************************************************************
     *                       Constructor                         *
     *************************************************************/
    constructor(ConstructorParams memory params) Ownable(params.owner) {
        LON_TOKEN_ADDR = params.lonTokenAddr;
        SUSHISWAP_ROUTER_ADDRESS = params.sushiRouterAddr;
        UNISWAP_V2_ROUTER_02_ADDRESS = params.uniswapV2RouterAddr;
        UNISWAP_V3_ROUTER_ADDRESS = params.uniswapV3RouterAddr;
        MIN_BUYBACK_INTERVAL = params.minBuyBackInterval;

        isOperator[params.operator] = true;

        buybackInterval = params.buyBackInterval;

        require(params.miningFactor <= 100, "incorrect mining factor");
        miningFactor = params.miningFactor;

        require(Address.isContract(params.lonStaking), "Lon staking is not a contract");
        treasury = params.treasury;
        lonStaking = params.lonStaking;
        miningTreasury = params.miningTreasury;
        feeTokenRecipient = params.feeTokenRecipient;
    }

    /************************************************************
     *                     Getter functions                      *
     *************************************************************/
    function getFeeTokenAMMRoute(address _feeTokenAddr) public view returns (bytes memory encodedAMMRoute) {
        return feeTokens[_feeTokenAddr].encodedAMMRoute;
    }

    /************************************************************
     *             Management functions for Owner                *
     *************************************************************/
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function setOperator(address _operator, bool _enable) external onlyOwner {
        isOperator[_operator] = _enable;

        emit SetOperator(_operator, _enable);
    }

    function setMiningFactor(uint8 _miningFactor) external onlyOwner {
        require(_miningFactor <= 100, "incorrect mining factor");

        miningFactor = _miningFactor;
        emit SetMiningFactor(_miningFactor);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    function setLonStaking(address _lonStaking) external onlyOwner {
        require(Address.isContract(_lonStaking), "Lon staking is not a contract");

        lonStaking = _lonStaking;
        emit SetLonStaking(_lonStaking);
    }

    function setMiningTreasury(address _miningTreasury) external onlyOwner {
        miningTreasury = _miningTreasury;
        emit SetMiningTreasury(_miningTreasury);
    }

    function setFeeTokenRecipient(address _feeTokenRecipient) external onlyOwner {
        feeTokenRecipient = _feeTokenRecipient;
        emit SetFeeTokenRecipient(_feeTokenRecipient);
    }

    /************************************************************
     *           Management functions for Operator               *
     *************************************************************/

    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external only_Operator_or_Owner {
        IERC20(_tokenAddress).safeTransfer(owner, _tokenAmount);
        emit Recovered(_tokenAddress, _tokenAmount);
    }

    function setBuybackInterval(uint32 _buyBackInterval) external only_Operator_or_Owner {
        require(_buyBackInterval >= 3600, "invalid buyback interval");

        buybackInterval = _buyBackInterval;
        emit SetBuybackInterval(_buyBackInterval);
    }

    function setStrategyAddrs(uint256[] calldata _indexes, address[] calldata _strategyAddrs) external only_Operator_or_Owner {
        require(_indexes.length == _strategyAddrs.length, "input not the same length");

        for (uint256 i = 0; i < _indexes.length; i++) {
            require(Address.isContract(_strategyAddrs[i]), "strategy is not a contract");
            require(_indexes[i] <= numStrategyAddr, "index out of bound");

            strategyAddrs[_indexes[i]] = _strategyAddrs[i];
            if (_indexes[i] == numStrategyAddr) numStrategyAddr++;
            emit SetStrategy(_indexes[i], _strategyAddrs[i]);
        }
    }

    function setFeeToken(
        address _feeTokenAddr,
        bytes memory _encodedAMMRoute,
        uint8 _LFactor,
        uint8 _RFactor,
        bool _enable,
        uint256 _minBuy,
        uint256 _maxBuy
    ) external only_Owner_or_Operator_or_Self {
        // Validate fee token inputs
        require(Address.isContract(_feeTokenAddr), "fee token is not a contract");
        require(_LFactor <= 100, "incorrect LFactor");
        require(_RFactor <= 100, "incorrect RFactor");
        require(_minBuy <= _maxBuy, "incorrect minBuy and maxBuy");

        uint8 _exchangeIndex = uint8(uint256(_encodedAMMRoute.readBytes32(0)));
        require(_exchangeIndex < 3, "invalid exchange index");
        if (_exchangeIndex == UNISWAP_V2_INDEX || _exchangeIndex == SUSHISWAP_INDEX) {
            (, address[] memory _decodedPath) = abi.decode(_encodedAMMRoute, (uint8, address[]));
            require(_decodedPath.length >= 2, "invalid Sushiswap/Uniswap v2 swap path");
            require(_decodedPath[_decodedPath.length - 1] == LON_TOKEN_ADDR, "output token must be LON");
        } else if (_exchangeIndex == UNISWAP_V3_INDEX) {
            (, bytes memory _decodedPath) = abi.decode(_encodedAMMRoute, (uint8, bytes));
            require(_decodedPath.numPools() >= 1, "invalid Uniswap v3 swap path");
        }

        FeeToken storage feeToken = feeTokens[_feeTokenAddr];
        feeToken.encodedAMMRoute = _encodedAMMRoute;
        feeToken.LFactor = _LFactor;
        feeToken.RFactor = _RFactor;
        if (feeToken.enable != _enable) {
            feeToken.enable = _enable;
            emit EnableFeeToken(_feeTokenAddr, _enable);
        }
        feeToken.minBuy = _minBuy;
        feeToken.maxBuy = _maxBuy;
        emit SetFeeToken(_feeTokenAddr, _encodedAMMRoute, _LFactor, _RFactor, _minBuy, _maxBuy);
    }

    function setFeeTokens(
        address[] memory _feeTokenAddr,
        bytes[] memory _encodedAMMRoute,
        uint8[] memory _LFactor,
        uint8[] memory _RFactor,
        bool[] memory _enable,
        uint256[] memory _minBuy,
        uint256[] memory _maxBuy
    ) external only_Operator_or_Owner {
        uint256 inputLength = _feeTokenAddr.length;
        require(
            (_encodedAMMRoute.length == inputLength) &&
                (_LFactor.length == inputLength) &&
                (_RFactor.length == inputLength) &&
                (_enable.length == inputLength) &&
                (_minBuy.length == inputLength) &&
                (_maxBuy.length == inputLength),
            "input not the same length"
        );

        for (uint256 i = 0; i < inputLength; i++) {
            try this.setFeeToken(_feeTokenAddr[i], _encodedAMMRoute[i], _LFactor[i], _RFactor[i], _enable[i], _minBuy[i], _maxBuy[i]) {
                continue;
            } catch Error(string memory reason) {
                emit SetFeeTokenFailure(_feeTokenAddr[i], reason, bytes(""));
            } catch (bytes memory lowLevelData) {
                emit SetFeeTokenFailure(_feeTokenAddr[i], "", lowLevelData);
            }
        }
    }

    function enableFeeToken(address _feeTokenAddr, bool _enable) external only_Operator_or_Owner {
        FeeToken storage feeToken = feeTokens[_feeTokenAddr];
        if (feeToken.enable != _enable) {
            feeToken.enable = _enable;
            emit EnableFeeToken(_feeTokenAddr, _enable);
        }
    }

    function enableFeeTokens(address[] calldata _feeTokenAddr, bool[] calldata _enable) external only_Operator_or_Owner {
        require(_feeTokenAddr.length == _enable.length, "input not the same length");

        for (uint256 i = 0; i < _feeTokenAddr.length; i++) {
            FeeToken storage feeToken = feeTokens[_feeTokenAddr[i]];
            if (feeToken.enable != _enable[i]) {
                feeToken.enable = _enable[i];
                emit EnableFeeToken(_feeTokenAddr[i], _enable[i]);
            }
        }
    }

    function _isAuthorized(address _account) internal view returns (bool) {
        if ((isOperator[_account]) || (_account == owner)) return true;
        else return false;
    }

    function _validate(FeeToken memory _feeToken, uint256 _amount) internal view returns (uint256 amountFeeTokenToSwap, uint256 amountFeeTokenToTransfer) {
        require(_amount > 0, "zero fee token amount");
        if (!_isAuthorized(msg.sender)) {
            require(_feeToken.enable, "fee token is not enabled");
        }

        amountFeeTokenToTransfer = _amount.mul(_feeToken.LFactor).div(100);
        amountFeeTokenToSwap = _amount.sub(amountFeeTokenToTransfer);

        if (amountFeeTokenToSwap > 0) {
            require(amountFeeTokenToSwap >= _feeToken.minBuy, "amount less than min buy");
            require(amountFeeTokenToSwap <= _feeToken.maxBuy, "amount greater than max buy");
            require(block.timestamp > uint256(_feeToken.lastTimeBuyback).add(uint256(buybackInterval)), "already a buyback recently");
        }
    }

    function _transferFeeToken(
        address _feeTokenAddr,
        address _transferTo,
        uint256 _totalFeeTokenAmount
    ) internal {
        address strategyAddr;
        uint256 balanceInStrategy;
        uint256 amountToTransferFrom;
        uint256 cumulatedAmount;
        for (uint256 i = 0; i < numStrategyAddr; i++) {
            strategyAddr = strategyAddrs[i];
            balanceInStrategy = IERC20(_feeTokenAddr).balanceOf(strategyAddr);
            if (cumulatedAmount.add(balanceInStrategy) > _totalFeeTokenAmount) {
                amountToTransferFrom = _totalFeeTokenAmount.sub(cumulatedAmount);
            } else {
                amountToTransferFrom = balanceInStrategy;
            }
            if (amountToTransferFrom == 0) continue;
            IERC20(_feeTokenAddr).safeTransferFrom(strategyAddr, _transferTo, amountToTransferFrom);

            cumulatedAmount = cumulatedAmount.add(amountToTransferFrom);
            if (cumulatedAmount == _totalFeeTokenAmount) break;
        }
        require(cumulatedAmount == _totalFeeTokenAmount, "insufficient amount of fee tokens");
    }

    function _swap(
        address _feeTokenAddr,
        bytes memory _encodedAMMRoute,
        uint256 _amountFeeTokenToSwap,
        uint256 _minLonAmount
    ) internal returns (uint256 swappedLonAmount) {
        uint8 _exchangeIndex = uint8(uint256(_encodedAMMRoute.readBytes32(0)));
        if (_exchangeIndex == UNISWAP_V2_INDEX || _exchangeIndex == SUSHISWAP_INDEX) {
            // Uniswap v2 and Sushiswap case
            address _exchangeAddr = (_exchangeIndex == UNISWAP_V2_INDEX) ? UNISWAP_V2_ROUTER_02_ADDRESS : SUSHISWAP_ROUTER_ADDRESS;

            // Decode path
            (, address[] memory _decodedPath) = abi.decode(_encodedAMMRoute, (uint8, address[]));

            // Approve exchange contract
            IERC20(_feeTokenAddr).safeApprove(_exchangeAddr, MAX_UINT);

            // Swap fee token for Lon
            IUniswapRouterV2 router = IUniswapRouterV2(_exchangeAddr);
            uint256[] memory amounts = router.swapExactTokensForTokens(
                _amountFeeTokenToSwap,
                _minLonAmount, // Minimum amount of Lon expected to receive
                _decodedPath,
                address(this),
                block.timestamp + 60
            );
            swappedLonAmount = amounts[_decodedPath.length - 1];

            // Clear allowance for exchange contract
            IERC20(_feeTokenAddr).safeApprove(_exchangeAddr, 0);
        } else if (_exchangeIndex == UNISWAP_V3_INDEX) {
            // Uniswap v3 case
            address _exchangeAddr = UNISWAP_V3_ROUTER_ADDRESS;

            // Decode path
            (, bytes memory _decodedPath) = abi.decode(_encodedAMMRoute, (uint8, bytes));

            // Approve exchange contract
            IERC20(_feeTokenAddr).safeApprove(_exchangeAddr, MAX_UINT);

            // Swap fee token for Lon
            ISwapRouter router = ISwapRouter(_exchangeAddr);
            ISwapRouter.ExactInputParams memory exactInputParams;
            exactInputParams.path = _decodedPath;
            exactInputParams.recipient = address(this);
            exactInputParams.deadline = block.timestamp + 60;
            exactInputParams.amountIn = _amountFeeTokenToSwap;
            exactInputParams.amountOutMinimum = _minLonAmount;
            swappedLonAmount = router.exactInput(exactInputParams);

            // Clear allowance for exchange contract
            IERC20(_feeTokenAddr).safeApprove(_exchangeAddr, 0);
        }
    }

    function _distributeLon(FeeToken memory _feeToken, uint256 swappedLonAmount) internal {
        // To Treasury
        uint256 treasuryAmount = swappedLonAmount.mul(_feeToken.RFactor).div(100);
        if (treasuryAmount > 0) {
            IERC20(LON_TOKEN_ADDR).safeTransfer(treasury, treasuryAmount);
        }

        // To LonStaking
        uint256 lonStakingAmount = swappedLonAmount.sub(treasuryAmount);
        if (lonStakingAmount > 0) {
            IERC20(LON_TOKEN_ADDR).safeTransfer(lonStaking, lonStakingAmount);
        }

        emit DistributeLon(treasuryAmount, lonStakingAmount);
    }

    function _mintLon(uint256 swappedLonAmount) internal {
        // Mint Lon for MiningTreasury
        uint256 mintedAmount = swappedLonAmount.mul(uint256(miningFactor)).div(100);
        if (mintedAmount > 0) {
            ILon(LON_TOKEN_ADDR).mint(miningTreasury, mintedAmount);
            emit MintLon(mintedAmount);
        }
    }

    function _buyback(
        address _feeTokenAddr,
        FeeToken storage _feeToken,
        uint256 _amountFeeTokenToSwap,
        uint256 _minLonAmount
    ) internal {
        if (_amountFeeTokenToSwap > 0) {
            uint256 swappedLonAmount = _swap(_feeTokenAddr, _feeToken.encodedAMMRoute, _amountFeeTokenToSwap, _minLonAmount);

            // Update fee token data
            _feeToken.lastTimeBuyback = uint32(block.timestamp);

            emit BuyBack(_feeTokenAddr, _amountFeeTokenToSwap, swappedLonAmount, _feeToken.LFactor, _feeToken.RFactor, _feeToken.minBuy, _feeToken.maxBuy);

            _distributeLon(_feeToken, swappedLonAmount);
            _mintLon(swappedLonAmount);
        }
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    function buyback(
        address _feeTokenAddr,
        uint256 _amount,
        uint256 _minLonAmount
    ) external whenNotPaused only_EOA_or_Self nonReentrant {
        FeeToken storage feeToken = feeTokens[_feeTokenAddr];

        // Distribute LON directly without swap
        if (_feeTokenAddr == LON_TOKEN_ADDR) {
            require(feeToken.enable, "fee token is not enabled");
            require(_amount >= feeToken.minBuy, "amount less than min buy");
            uint256 _lonToTreasury = _amount.mul(feeToken.RFactor).div(100);
            uint256 _lonToStaking = _amount.sub(_lonToTreasury);
            _transferFeeToken(LON_TOKEN_ADDR, treasury, _lonToTreasury);
            _transferFeeToken(LON_TOKEN_ADDR, lonStaking, _lonToStaking);
            emit DistributeLon(_lonToTreasury, _lonToStaking);
            _mintLon(_amount);

            // Update lastTimeBuyback
            feeToken.lastTimeBuyback = uint32(block.timestamp);
            return;
        }

        // Validate fee token data and input amount
        (uint256 amountFeeTokenToSwap, uint256 amountFeeTokenToTransfer) = _validate(feeToken, _amount);

        if (amountFeeTokenToSwap == 0) {
            // No need to swap, transfer feeToken directly
            _transferFeeToken(_feeTokenAddr, feeTokenRecipient, amountFeeTokenToTransfer);
        } else {
            // Transfer fee token from strategy contracts to distributor
            _transferFeeToken(_feeTokenAddr, address(this), _amount);

            // Buyback
            _buyback(_feeTokenAddr, feeToken, amountFeeTokenToSwap, _minLonAmount);

            // Transfer fee token from distributor to feeTokenRecipient
            if (amountFeeTokenToTransfer > 0) {
                IERC20(_feeTokenAddr).safeTransfer(feeTokenRecipient, amountFeeTokenToTransfer);
            }
        }
    }

    function batchBuyback(
        address[] calldata _feeTokenAddr,
        uint256[] calldata _amount,
        uint256[] calldata _minLonAmount
    ) external whenNotPaused only_EOA {
        uint256 inputLength = _feeTokenAddr.length;
        require((_amount.length == inputLength) && (_minLonAmount.length == inputLength), "input not the same length");

        for (uint256 i = 0; i < inputLength; i++) {
            try this.buyback(_feeTokenAddr[i], _amount[i], _minLonAmount[i]) {
                continue;
            } catch Error(string memory reason) {
                emit BuyBackFailure(_feeTokenAddr[i], _amount[i], reason, bytes(""));
            } catch (bytes memory lowLevelData) {
                emit BuyBackFailure(_feeTokenAddr[i], _amount[i], "", lowLevelData);
            }
        }
    }
}
