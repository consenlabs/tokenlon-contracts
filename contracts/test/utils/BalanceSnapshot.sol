pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Addresses.sol";

library BalanceSnapshot {
    struct Snapshot {
        address owner;
        IERC20 token;
        int256 balanceBefore; // Assume max balance is type(int256).max
    }

    function take(address owner, address token) internal view returns (Snapshot memory) {
        uint256 balanceBefore;
        if (token == Addresses.ETH_ADDRESS) {
            balanceBefore = owner.balance;
        } else {
            balanceBefore = IERC20(token).balanceOf(owner);
        }
        return Snapshot(owner, IERC20(token), int256(balanceBefore));
    }

    function _getBalanceAfter(Snapshot memory snapshot) internal view returns (int256) {
        if (address(snapshot.token) == Addresses.ETH_ADDRESS) {
            return int256(snapshot.owner.balance);
        } else {
            return int256(snapshot.token.balanceOf(snapshot.owner));
        }
    }

    function assertChange(Snapshot memory snapshot, int256 expectedChange) internal view {
        int256 balanceAfter = _getBalanceAfter(snapshot);
        require(int256(balanceAfter) - snapshot.balanceBefore == expectedChange, "Not expected balance change");
    }

    function assertChangeGt(Snapshot memory snapshot, int256 expectedMinChange) internal view {
        int256 balanceAfter = _getBalanceAfter(snapshot);
        int256 balanceChange = balanceAfter - snapshot.balanceBefore;
        bool sameSign = (balanceChange >= int256(0) && expectedMinChange >= int256(0)) || (balanceChange <= int256(0) && expectedMinChange <= int256(0));
        require(sameSign, "Actual and expected change do not have the same sign");

        if (balanceChange > int256(0)) {
            require(balanceChange >= expectedMinChange, "Not expected balance change");
        } else {
            require(balanceChange < expectedMinChange, "Not expected balance change");
        }
    }
}
