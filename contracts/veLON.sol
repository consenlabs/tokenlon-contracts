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
    uint256 internal constant MULTIPLIER = 1 ether;
    address public immutable token;

    uint256 public tokenSupply;
    uint256 public epoch;
    uint256 public maxLockDuration = 365 days;
    uint256 public earlyWithdrawPenaltyRate = 3000;

    mapping(uint256 => Point) public poolPointHistory; // epoch -> unsignd point
    mapping(uint256 => Point[1000000000]) public userPointHistory; // user -> Point[user_epoch]
    mapping(uint256 => LockedBalance) public locked; // tokenId -> locked balance
    mapping(uint256 => uint256) public userPointEpoch; // tokenId -> epoch
    mapping(uint256 => int256) public dRateChanges; // time -> signed declining rate change

    /// @dev Current count of token
    uint256 internal tokenId;

    /// @notice Contract constructor
    /// @param _tokenAddr token address
    constructor(address _tokenAddr) ERC721("veLON NFT", "veLON") Ownable(msg.sender) {
        token = _tokenAddr;

        poolPointHistory[0].blk = block.number;
        poolPointHistory[0].ts = block.timestamp;
    }

    /// @notice Update the `maxLockDuration`.
    /// @param _maxLockDuration new number of seconds for `maxLockDuration`.
    function setMaxLockDuration(uint256 _maxLockDuration) external override onlyOwner {
        // flush the global voting power change into storage first
        _checkpoint(0, LockedBalance(0, 0), LockedBalance(0, 0));

        uint256 maxEndTime = block.timestamp.add(_maxLockDuration).div(WEEK).mul(WEEK);
        int256 globalSlope;
        int256 globalBias;
        // update every NFT's stored states and calculate global states
        for (uint256 _tokenId = 0; _tokenId <= tokenId; _tokenId++) {
            // skip NFTs that have been burned
            if (ownerOf(_tokenId) == address(0)) {
                continue;
            }
            // skip expired NFTs
            if (locked[_tokenId].end < block.timestamp) {
                continue;
            }

            uint256 userEpoch = userPointEpoch[_tokenId];
            LockedBalance memory oldLocked = locked[_tokenId];
            LockedBalance memory newLocked = locked[_tokenId];
            Point memory pointOld = userPointHistory[_tokenId][userEpoch];
            Point memory pointNew = Point({ bias: 0, slope: 0, ts: block.timestamp, blk: block.number });
            if (newLocked.end > maxEndTime) {
                newLocked.end = maxEndTime;
            }
            pointNew.slope = int256(newLocked.amount.div(_maxLockDuration));
            int256 duration = int256(newLocked.end.sub(block.timestamp));
            pointNew.bias = duration * pointNew.slope;

            // update the latest user epoch and user point
            userEpoch = userEpoch.add(1);
            userPointEpoch[_tokenId] = userEpoch;
            userPointHistory[_tokenId][userEpoch] = pointNew;

            // update slope_changes
            slopeChanges[oldLocked.end] += pointOld.slope;
            slopeChanges[newLocked.end] += pointNew.slope;

            globalSlope += pointNew.slope;
            globalBias += pointNew.bias;
        }

        // update global point
        epoch = epoch.add(1);
        poolPointHistory[epoch] = Point({ bias: globalBias, slope: globalSlope, ts: block.timestamp, blk: block.number });

        // update the maxLockDuration
        maxLockDuration = _maxLockDuration;
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
        _lockedBalance.amount += _value;
        if (_unlockTime != 0) {
            _lockedBalance.end = _unlockTime;
        }
        locked[_tokenId] = _lockedBalance;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // _locked.end > block.timestamp (always)
        _updateLockedPoint(_tokenId, _oldLocked, _lockedBalance);

        if (_value != 0 && _depositType != DepositType.MERGE_TYPE) {
            assert(IERC20(token).transferFrom(msg.sender, address(this), _value));
        }

        emit Deposit(msg.sender, _tokenId, _value, _lockedBalance.end, _depositType, block.timestamp);
    }

    /// @notice Withdraw all tokens for `_tokenId`
    /// @param _tokenId NFT that holds lock
    function withdraw(uint256 _tokenId) external override nonReentrant {
        _withdraw(_tokenId, false);
    }

    /// @notice Withdraw all tokens for `_tokenId` and allow penalty if not expired yet
    /// @param _tokenId NFT that holds lock
    function withdrawEarly(uint256 _tokenId) external override nonReentrant {
        _withdraw(_tokenId, true);
    }

    function _withdraw(uint256 _tokenId, bool _allowPenalty) private {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");

        LockedBalance memory _locked = locked[_tokenId];
        uint256 amount = _locked.amount;
        bool expired = block.timestamp >= _locked.end;
        require(expired || _allowPenalty, "Lock has not ended");

        locked[_tokenId] = LockedBalance(0, 0);
        tokenSupply = tokenSupply.sub(amount);

        _updateLockedPoint(_tokenId, _locked, LockedBalance(0, 0));

        // Burn the NFT
        address owner = ownerOf(_tokenId);
        _burn(_tokenId);

        uint256 penalty = 0;
        if (!expired) {
            penalty = (amount.mul(earlyWithdrawPenaltyRate)).div(PENALTY_RATE_PRECISION);
            amount = amount.sub(penalty);
            ILon(token).burn(penalty);
        }
        require(IERC20(token).transfer(owner, amount), "Token withdraw failed");

        emit Withdraw(msg.sender, expired, _tokenId, amount, penalty, block.timestamp);
    }

    /// @notice Merge two locking NFTs as one
    /// @param _from NFT that holds lock and to be burned
    /// @param _to NFT that holds lock and to be updated
    function merge(uint256 _from, uint256 _to) external override {
        require(_from != _to, "Same NFT ids");
        require(_isApprovedOrOwner(msg.sender, _from), "Not approved or owner of from");
        require(_isApprovedOrOwner(msg.sender, _to), "Not approved or owner of to");

        LockedBalance memory _lockedFrom = locked[_from];
        LockedBalance memory _lockedTo = locked[_to];
        uint256 value0 = _lockedFrom.amount;
        uint256 end = _lockedFrom.end >= _lockedTo.end ? _lockedFrom.end : _lockedTo.end;

        locked[_from] = LockedBalance(0, 0);
        _updateLockedPoint(_from, _lockedFrom, LockedBalance(0, 0));
        _burn(_from);
        _depositFor(_to, value0, end, _lockedTo, DepositType.MERGE_TYPE);
    }

    /// @notice Record global and per-user data to storage
    /// @param _tokenId NFT token ID
    /// @param _oldLocked Pevious locked amount / end lock time for the user, to be replaced by new one
    /// @param _newLocked New locked amount / end lock time for the user
    function _updateLockedPoint(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        LockedBalance memory _newLocked
    ) private {
        Point memory pointOld;
        Point memory pointNew;
        int256 dSlopeOld = 0;
        int256 dSlopeNew = 0;
        uint256 _epoch = epoch;

        // Calculate decliningRates and vBalances
        // Kept at zero if not active anymore
        if (_lockIsActive(_oldLocked)) {
            pointOld.decliningRate = int256(_oldLocked.amount / maxLockDuration);
            pointOld.vBalance = pointOld.decliningRate * int256(_oldLocked.end - block.timestamp);
        }
        if (_lockIsActive(_newLocked)) {
            pointNew.decliningRate = int256(_newLocked.amount / maxLockDuration);
            pointNew.vBalance = pointNew.decliningRate * int256(_newLocked.end - block.timestamp);
        }

        // Read values of scheduled changes in the decliningRate
        // _oldLocked.end can be in the past and in the future
        // _newLocked.end can ONLY by in the FUTURE unless everything expired: than zeros
        dSlopeOld = dRateChanges[_oldLocked.end];
        if (_newLocked.end != 0) {
            if (_newLocked.end == _oldLocked.end) {
                dSlopeNew = dSlopeOld;
            } else {
                dSlopeNew = dRateChanges[_newLocked.end];
            }
        }

        Point memory poolLastPoint = Point({ vBalance: 0, decliningRate: 0, ts: block.timestamp, blk: block.number });
        if (_epoch > 0) {
            poolLastPoint = poolPointHistory[_epoch];
        }

        (poolLastPoint, _epoch) = _syncGlobalPoints(poolLastPoint, _epoch);

        // If last point was in this block, the decliningRate change has been applied already
        // But in such case we have 0 decliningRate(s)
        poolLastPoint.decliningRate += (pointNew.decliningRate - pointOld.decliningRate);
        poolLastPoint.vBalance += (pointNew.vBalance - pointOld.vBalance);
        if (poolLastPoint.decliningRate < 0) {
            poolLastPoint.decliningRate = 0;
        }
        if (poolLastPoint.vBalance < 0) {
            poolLastPoint.vBalance = 0;
        }

        // Record the changed point into history
        poolPointHistory[_epoch] = poolLastPoint;
        // Sync storage variable now
        epoch = _epoch;

        // Schedule the decliningRate changes (decliningRate is going down)
        // We subtract new_user_decliningRate from [_newLocked.end]
        // and add old_user_decliningRate to [_oldLocked.end]
        if (_oldLocked.end > block.timestamp) {
            // dSlopeOld was <something> - pointOld.decliningRate, so we cancel that
            dSlopeOld += pointOld.decliningRate;
            if (_newLocked.end == _oldLocked.end) {
                dSlopeOld -= pointNew.decliningRate; // It was a new deposit, not extension
            }
            dRateChanges[_oldLocked.end] = dSlopeOld;
        }

        if (_newLocked.end > block.timestamp) {
            if (_newLocked.end > _oldLocked.end) {
                dSlopeNew -= pointNew.decliningRate; // old decliningRate disappeared at this point
                dRateChanges[_newLocked.end] = dSlopeNew;
            }
            // else: we recorded it already in dSlopeOld
        }
        // Now handle user history
        uint256 user_epoch = userPointEpoch[_tokenId] + 1;

        userPointEpoch[_tokenId] = user_epoch;
        pointNew.ts = block.timestamp;
        pointNew.blk = block.number;
        userPointHistory[_tokenId][user_epoch] = pointNew;
    }

    // Go over weeks to fill history and calculate what the current pool point is
    function _syncGlobalPoints(Point memory poolLastPoint, uint256 _epoch) private returns (Point memory, uint256) {
        // block slope = dBlock/dTime
        // If last point is already recorded in this block, slope=0
        // But that's ok because we know the block in such case
        uint256 blockSlope = 0;
        if (block.timestamp > poolLastPoint.ts) {
            blockSlope = (MULTIPLIER * (block.number - poolLastPoint.blk)) / (block.timestamp - poolLastPoint.ts);
        }

        uint256 timeStart = poolLastPoint.ts;
        // initial_poolLastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory initial_poolLastPoint = poolLastPoint;
        uint256 timeEnd = ((timeStart / WEEK) * WEEK) + WEEK;
        for (uint256 i = 0; i < 255; ++i) {
            // Assume it won't exceed 255 weeks since last time pool point updated.
            // If it does, users will be able to withdraw but vote weight will be broken
            int256 dSlope = 0;
            if (timeEnd > block.timestamp) {
                timeEnd = block.timestamp;
            } else {
                dSlope = dRateChanges[timeEnd];
            }

            // update decliningRate and vBalance
            poolLastPoint.vBalance -= poolLastPoint.decliningRate * (int256(timeEnd - timeStart));
            poolLastPoint.decliningRate += dSlope;
            if (poolLastPoint.vBalance < 0) {
                // This can happen
                poolLastPoint.vBalance = 0;
            }
            if (poolLastPoint.decliningRate < 0) {
                // This cannot happen - just in case
                poolLastPoint.decliningRate = 0;
            }

            // update ts and block (approximately block number)
            poolLastPoint.ts = timeEnd;
            poolLastPoint.blk = initial_poolLastPoint.blk + (blockSlope * (timeEnd - initial_poolLastPoint.ts)) / MULTIPLIER;

            if (timeEnd == block.timestamp) {
                poolLastPoint.blk = block.number;
                // poolLastPoint may needs to be adjusted using user points and record in new epoch index
                return (poolLastPoint, _epoch + 1);
            } else {
                poolPointHistory[_epoch] = poolLastPoint;
            }

            // move time window and continue
            _epoch += 1;
            timeStart = timeEnd;
            timeEnd += WEEK;
        }

        // should not reach here
        revert();
    }

    function _lockIsActive(LockedBalance memory lock) private returns (bool) {
        return lock.end > block.timestamp && lock.amount > 0;
    }
}
