// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol";

interface IveLON is IERC721, IERC721Metadata {
    enum DepositType {
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE
    }

    struct LockedBalance {
        uint256 amount;
        uint256 end;
    }

    struct Point {
        int256 vBalance;
        int256 decliningRate; // # -dweight / dt
        uint256 ts;
        uint256 blk;
    }

    event Deposit(address indexed provider, uint256 tokenId, uint256 value, uint256 indexed locktime, DepositType depositType, uint256 ts);
    event Withdraw(address indexed provider, bool indexed lockExpired, uint256 tokenId, uint256 withdrawValue, uint256 burnValue, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    function vBalanceOf(uint256 _tokenId) external view returns (uint256);

    function vBalanceOfAtTime(uint256 _tokenId, uint256 _t) external view returns (uint256);

    function vBalanceOfAtBlk(uint256 _tokenId, uint256 _block) external view returns (uint256);

    function unlockTime(uint256 _tokenId) external view returns (uint256);

    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256);

    function extendLock(uint256 _tokenId, uint256 _lock_duration) external;

    function depositFor(uint256 _tokenId, uint256 _value) external;

    function withdraw(uint256 _tokenId) external;

    function withdrawEarly(uint256 _tokenId) external;

    function merge(uint256 _from, uint256 _to) external;

    function totalvBalance() external view returns (uint256);

    function totalvBalanceAtTime(uint256 t) external view returns (uint256);

    function totalvBalanceAtBlk(uint256 _block) external view returns (uint256);
}
