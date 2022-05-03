// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

/* Modified from SushiBar contract: https://etherscan.io/address/0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272#code */
/* Added with AAVE StakedToken's cooldown feature: https://etherscan.io/address/0x74a7a4e7566a2f523986e500ce35b20d343f6741#code */

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/ILon.sol";
import "./upgradeable/ERC20ForUpgradeable.sol";
import "./upgradeable/OwnableForUpgradeable.sol";

contract LONStaking is ERC20ForUpgradeable, OwnableForUpgradeable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for ILon;
    using SafeERC20 for IERC20;

    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    uint256 private constant BPS_MAX = 10000;

    ILon public lonToken;
    bytes32 public DOMAIN_SEPARATOR;
    uint256 public BPS_RAGE_EXIT_PENALTY;
    uint256 public COOLDOWN_SECONDS;
    uint256 public COOLDOWN_IN_DAYS;
    mapping(address => uint256) public nonces; // For EIP-2612 permit()
    mapping(address => uint256) public stakersCooldowns;

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount, uint256 share);
    event Cooldown(address indexed user);
    event Redeem(address indexed user, uint256 share, uint256 redeemAmount, uint256 penaltyAmount);
    event Recovered(address token, uint256 amount);
    event SetCooldownAndRageExitParam(uint256 coolDownInDays, uint256 bpsRageExitPenalty);

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        ILon _lonToken,
        address _owner,
        uint256 _COOLDOWN_IN_DAYS,
        uint256 _BPS_RAGE_EXIT_PENALTY
    ) external {
        lonToken = _lonToken;

        _initializeOwnable(_owner);
        _initializeERC20("Wrapped Tokenlon", "xLON");

        require(_COOLDOWN_IN_DAYS >= 1, "COOLDOWN_IN_DAYS less than 1 day");
        require(_BPS_RAGE_EXIT_PENALTY <= BPS_MAX, "BPS_RAGE_EXIT_PENALTY larger than BPS_MAX");
        COOLDOWN_IN_DAYS = _COOLDOWN_IN_DAYS;
        COOLDOWN_SECONDS = _COOLDOWN_IN_DAYS * 86400;
        BPS_RAGE_EXIT_PENALTY = _BPS_RAGE_EXIT_PENALTY;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function setCooldownAndRageExitParam(uint256 _COOLDOWN_IN_DAYS, uint256 _BPS_RAGE_EXIT_PENALTY) public onlyOwner {
        require(_COOLDOWN_IN_DAYS >= 1, "COOLDOWN_IN_DAYS less than 1 day");
        require(_BPS_RAGE_EXIT_PENALTY <= BPS_MAX, "BPS_RAGE_EXIT_PENALTY larger than BPS_MAX");

        COOLDOWN_IN_DAYS = _COOLDOWN_IN_DAYS;
        COOLDOWN_SECONDS = _COOLDOWN_IN_DAYS * 86400;
        BPS_RAGE_EXIT_PENALTY = _BPS_RAGE_EXIT_PENALTY;
        emit SetCooldownAndRageExitParam(_COOLDOWN_IN_DAYS, _BPS_RAGE_EXIT_PENALTY);
    }

    function recoverERC20(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(lonToken), "cannot withdraw lon token");
        IERC20(_tokenAddress).safeTransfer(owner, _tokenAmount);
        emit Recovered(_tokenAddress, _tokenAmount);
    }

    /* ========== VIEWS ========== */

    function cooldownRemainSeconds(address _account) external view returns (uint256) {
        uint256 cooldownTimestamp = stakersCooldowns[_account];
        if ((cooldownTimestamp == 0) || (cooldownTimestamp.add(COOLDOWN_SECONDS) <= block.timestamp)) return 0;

        return cooldownTimestamp.add(COOLDOWN_SECONDS).sub(block.timestamp);
    }

    function previewRageExit(address _account) external view returns (uint256 receiveAmount, uint256 penaltyAmount) {
        uint256 cooldownEndTimestamp = stakersCooldowns[_account].add(COOLDOWN_SECONDS);
        uint256 totalLon = lonToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        uint256 share = balanceOf(_account);
        uint256 userTotalAmount = share.mul(totalLon).div(totalShares);

        if (block.timestamp > cooldownEndTimestamp) {
            // Normal redeem if cooldown period already passed
            receiveAmount = userTotalAmount;
            penaltyAmount = 0;
        } else {
            uint256 timeDiffInDays = Math.min(COOLDOWN_IN_DAYS, (cooldownEndTimestamp.sub(block.timestamp)).div(86400).add(1));
            // Penalty share = share * (number_of_days_to_cooldown_end / number_of_days_in_cooldown) * (BPS_RAGE_EXIT_PENALTY / BPS_MAX)
            uint256 penaltyShare = share.mul(timeDiffInDays).mul(BPS_RAGE_EXIT_PENALTY).div(BPS_MAX).div(COOLDOWN_IN_DAYS);
            receiveAmount = share.sub(penaltyShare).mul(totalLon).div(totalShares);
            penaltyAmount = userTotalAmount.sub(receiveAmount);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _getNextCooldownTimestamp(
        uint256 _fromCooldownTimestamp,
        uint256 _amountToReceive,
        address _toAddress,
        uint256 _toBalance
    ) internal returns (uint256) {
        uint256 toCooldownTimestamp = stakersCooldowns[_toAddress];
        if (toCooldownTimestamp == 0) {
            return 0;
        }

        uint256 fromCooldownTimestamp;
        // If sent from user who has not unstake, set fromCooldownTimestamp to current block timestamp,
        // i.e., pretend the user just unstake now.
        // This is to prevent user from bypassing cooldown by transferring to an already unstaked account.
        if (_fromCooldownTimestamp == 0) {
            fromCooldownTimestamp = block.timestamp;
        } else {
            fromCooldownTimestamp = _fromCooldownTimestamp;
        }

        // If `to` account has greater timestamp, i.e., `to` has to wait longer, the timestamp remains the same.
        if (fromCooldownTimestamp <= toCooldownTimestamp) {
            return toCooldownTimestamp;
        } else {
            // Otherwise, count in `from` account's timestamp to derive `to` account's new timestamp.

            // If the period between `from` and `to` account is greater than COOLDOWN_SECONDS,
            // reduce the period to COOLDOWN_SECONDS.
            // This is to prevent user from bypassing cooldown by early unstake with `to` account
            // and enjoy free cooldown bonus while waiting for `from` account to unstake.
            if (fromCooldownTimestamp.sub(toCooldownTimestamp) > COOLDOWN_SECONDS) {
                toCooldownTimestamp = fromCooldownTimestamp.sub(COOLDOWN_SECONDS);
            }

            toCooldownTimestamp = (_amountToReceive.mul(fromCooldownTimestamp).add(_toBalance.mul(toCooldownTimestamp))).div(_amountToReceive.add(_toBalance));
            return toCooldownTimestamp;
        }
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override whenNotPaused {
        uint256 balanceOfFrom = balanceOf(_from);
        uint256 balanceOfTo = balanceOf(_to);
        uint256 previousSenderCooldown = stakersCooldowns[_from];
        if (_from != _to) {
            stakersCooldowns[_to] = _getNextCooldownTimestamp(previousSenderCooldown, _amount, _to, balanceOfTo);
            // if cooldown was set and whole balance of sender was transferred - clear cooldown
            if (balanceOfFrom == _amount && previousSenderCooldown != 0) {
                stakersCooldowns[_from] = 0;
            }
        }

        super._transfer(_from, _to, _amount);
    }

    // EIP-2612 permit standard
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        require(_owner != address(0), "owner is zero address");
        require(block.timestamp <= _deadline || _deadline == 0, "permit expired");

        bytes32 digest = keccak256(
            abi.encodePacked(uint16(0x1901), DOMAIN_SEPARATOR, keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, nonces[_owner]++, _deadline)))
        );

        require(_owner == ecrecover(digest, _v, _r, _s), "invalid signature");
        _approve(_owner, _spender, _value);
    }

    function _stake(address _account, uint256 _amount) internal {
        require(_amount > 0, "cannot stake 0 amount");

        // Mint xLON according to current share and Lon amount
        uint256 totalLon = lonToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        uint256 share;
        if (totalShares == 0 || totalLon == 0) {
            share = _amount;
        } else {
            share = _amount.mul(totalShares).div(totalLon);
        }
        // Update staker's Cooldown timestamp
        stakersCooldowns[_account] = _getNextCooldownTimestamp(block.timestamp, share, _account, balanceOf(_account));

        _mint(_account, share);
        emit Staked(_account, _amount, share);
    }

    function stake(uint256 _amount) public nonReentrant whenNotPaused {
        _stake(msg.sender, _amount);
        lonToken.transferFrom(msg.sender, address(this), _amount);
    }

    function stakeWithPermit(
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public nonReentrant whenNotPaused {
        _stake(msg.sender, _amount);
        // Use permit to allow LONStaking contract to transferFrom user
        lonToken.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s);
        lonToken.transferFrom(msg.sender, address(this), _amount);
    }

    function unstake() public {
        require(balanceOf(msg.sender) > 0, "no share to unstake");
        require(stakersCooldowns[msg.sender] == 0, "already unstake");

        stakersCooldowns[msg.sender] = block.timestamp;
        emit Cooldown(msg.sender);
    }

    function _redeem(uint256 _share, uint256 _penalty) internal {
        require(_share != 0, "cannot redeem 0 share");

        uint256 totalLon = lonToken.balanceOf(address(this));
        uint256 totalShares = totalSupply();

        uint256 userTotalAmount = _share.add(_penalty).mul(totalLon).div(totalShares);
        uint256 redeemAmount = _share.mul(totalLon).div(totalShares);
        uint256 penaltyAmount = userTotalAmount.sub(redeemAmount);
        _burn(msg.sender, _share.add(_penalty));
        if (balanceOf(msg.sender) == 0) {
            stakersCooldowns[msg.sender] = 0;
        }

        lonToken.transfer(msg.sender, redeemAmount);

        emit Redeem(msg.sender, _share, redeemAmount, penaltyAmount);
    }

    function redeem(uint256 _share) public nonReentrant {
        uint256 cooldownStartTimestamp = stakersCooldowns[msg.sender];
        require(cooldownStartTimestamp > 0, "not yet unstake");

        require(block.timestamp > cooldownStartTimestamp.add(COOLDOWN_SECONDS), "Still in cooldown");

        _redeem(_share, 0);
    }

    function rageExit() public nonReentrant {
        uint256 cooldownStartTimestamp = stakersCooldowns[msg.sender];
        require(cooldownStartTimestamp > 0, "not yet unstake");

        uint256 cooldownEndTimestamp = cooldownStartTimestamp.add(COOLDOWN_SECONDS);
        uint256 share = balanceOf(msg.sender);
        if (block.timestamp > cooldownEndTimestamp) {
            // Normal redeem if cooldown period already passed
            _redeem(share, 0);
        } else {
            uint256 timeDiffInDays = Math.min(COOLDOWN_IN_DAYS, (cooldownEndTimestamp.sub(block.timestamp)).div(86400).add(1));
            // Penalty = share * (number_of_days_to_cooldown_end / number_of_days_in_cooldown) * (BPS_RAGE_EXIT_PENALTY / BPS_MAX)
            uint256 penalty = share.mul(timeDiffInDays).mul(BPS_RAGE_EXIT_PENALTY).div(BPS_MAX).div(COOLDOWN_IN_DAYS);
            _redeem(share.sub(penalty), penalty);
        }
    }
}
