// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol";

import "./interfaces/IveLON.sol";
import "./interfaces/ILon.sol";
import "./Ownable.sol";

contract veLON is IveLON, ERC721, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 private constant WEEK = 1 weeks;
    uint256 public constant PENALTY_RATE_PRECISION = 10000;
    address public immutable token;

    uint256 public tokenSupply;
    uint256 public maxLockDuration = 365 days;
    uint256 public earlyWithdrawPenaltyRate = 3000;

    mapping(uint256 => Point) public pointHistory; // epoch -> unsigned point
    mapping(uint256 => LockedBalance) public locked;

    /// @dev Current count of token
    uint256 internal tokenId;

    /// @notice Contract constructor
    /// @param _tokenAddr `ERC20CRV` token address
    constructor(address _tokenAddr) ERC721("veLON NFT", "veLON") Ownable(msg.sender) {
        token = _tokenAddr;

        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;
    }

    /// @notice Get timestamp when `_tokenId`'s lock finishes
    /// @param _tokenId User NFT
    /// @return Epoch time of the lock end
    function unlockTime(uint256 _tokenId) external view override returns (uint256) {
        return locked[_tokenId].end;
    }

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lock_duration`
    /// @param _value Amount to deposit
    /// @param _lockDuration Number of seconds to lock tokens for (rounded down to nearest week)
    function createLock(uint256 _value, uint256 _lockDuration) external override nonReentrant returns (uint256) {
        require(_value > 0, "Zero lock amount");

        // unlockTime is rounded down to weeks
        uint256 unlockTime = (block.timestamp).add(_lockDuration).div(WEEK).mul(WEEK);
        require(unlockTime > block.timestamp, "Lock duration too short");
        require(unlockTime <= (block.timestamp).add(maxLockDuration), "Unlock time exceed maximun");

        ++tokenId;
        uint256 _tokenId = tokenId;
        _safeMint(msg.sender, _tokenId);
        _depositFor(_tokenId, _value, unlockTime, locked[_tokenId], DepositType.CREATE_LOCK_TYPE);
        return _tokenId;
    }

    /// @notice Deposit `_value` tokens for `_tokenId` and add to the lock
    /// @dev Anyone (even a smart contract) can deposit for someone else, but
    ///      cannot extend their locktime and deposit for a brand new user
    /// @param _tokenId lock NFT
    /// @param _value Amount to add to user's lock
    function depositFor(uint256 _tokenId, uint256 _value) external override nonReentrant {
        require(_value > 0, "Zero deposit amount");

        LockedBalance memory _locked = locked[_tokenId];
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to expired lock");
        _depositFor(_tokenId, _value, 0, _locked, DepositType.DEPOSIT_FOR_TYPE);
    }

    /// @notice Extend the unlock time for `_tokenId`
    /// @param _tokenId lock NFT
    /// @param _lockDuration New number of seconds until tokens unlock
    function extendLock(uint256 _tokenId, uint256 _lockDuration) external override nonReentrant {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");

        LockedBalance memory _locked = locked[_tokenId];
        require(_locked.end > block.timestamp, "Lock expired");
        require(_locked.amount > 0, "Nothing is locked");

        uint256 unlockTime = (block.timestamp).add(_lockDuration).div(WEEK).mul(WEEK);
        require(unlockTime > _locked.end, "Can only increase lock duration");
        require(unlockTime <= (block.timestamp).add(maxLockDuration), "Unlock time exceed maximun");

        _depositFor(_tokenId, 0, unlockTime, _locked, DepositType.INCREASE_UNLOCK_TIME);
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param _unlockTime New time when to unlock the tokens, or 0 if unchanged
    /// @param _lockedBalance Previous locked amount / timestamp
    /// @param _depositType The type of deposit
    function _depositFor(
        uint256 _tokenId,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance memory _lockedBalance,
        DepositType _depositType
    ) private {
        tokenSupply = tokenSupply.add(_value);

        LockedBalance memory _oldLocked = LockedBalance(_lockedBalance.amount, _lockedBalance.end);

        // Adding to existing lock, or if a lock is expired - creating a new one
        _lockedBalance.amount += int128(int256(_value));
        if (_unlockTime != 0) {
            _lockedBalance.end = _unlockTime;
        }
        locked[_tokenId] = _lockedBalance;

        // Possibilities:
        // Both old_locked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _checkpoint(_tokenId, _oldLocked, _lockedBalance);

        if (_value != 0 && _depositType != DepositType.MERGE_TYPE) {
            assert(IERC20(token).transferFrom(msg.sender, address(this), _value));
        }

        emit Deposit(msg.sender, _tokenId, _value, _lockedBalance.end, _depositType, block.timestamp);
    }

    /// @notice Withdraw all tokens for `_tokenId`
    /// @param _tokenId NFT that holds lock
    function withdraw(uint256 _tokenId) external override nonReentrant {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");

        LockedBalance memory _locked = locked[_tokenId];
        bool expired = block.timestamp >= _locked.end;
        uint256 amount = uint256(int256(_locked.amount));

        locked[_tokenId] = LockedBalance(0, 0);
        uint256 supplyBefore = tokenSupply;
        tokenSupply = tokenSupply.sub(amount);

        // old_locked can have either expired <= timestamp or zero end
        // _locked has only 0 end
        // Both can have >= 0 amount
        _checkpoint(_tokenId, _locked, LockedBalance(0, 0));

        // Burn the NFT
        _burn(_tokenId);

        address owner = ownerOf(_tokenId);
        uint256 penalty = 0;
        if (!expired) {
            penalty = (amount.mul(earlyWithdrawPenaltyRate)).div(PENALTY_RATE_PRECISION);
            amount = amount.sub(penalty);
            ILon(token).burn(penalty);
        }
        require(IERC20(token).transfer(owner, amount), "Token withdraw failed");

        emit Withdraw(msg.sender, expired, _tokenId, amount, penalty, block.timestamp);
    }

    function _checkpoint(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        LockedBalance memory _lockedBalance
    ) private {
        // TODO to be implemented
    }
}
