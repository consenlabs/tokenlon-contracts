// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "contracts/TreasuryVester.sol";
import "contracts/TreasuryVesterFactory.sol";
import "contracts-test/mocks/MockERC20.sol";
import "contracts-test/utils/BalanceSnapshot.sol";

contract TreasuryVesterTest is Test {
    using SafeMath for uint256;
    using BalanceSnapshot for BalanceSnapshot.Snapshot;

    event VesterCreated(address indexed vester, address indexed recipient, uint256 vestingAmount);

    address recipient = address(0x133701);
    address other = address(0x133702);

    MockERC20 lon = new MockERC20("Tokenlon", "LON", 18);

    TreasuryVesterFactory treasuryVesterFactory;
    TreasuryVester treasuryVester;

    uint256 DEFAULT_VESTING_AMOUNT = 10000 * 1e18;
    uint256 DEFAULT_VESTING_BEGIN_TIMESTAMP = block.timestamp;
    uint256 DEFAULT_VESTING_CLIFF_TIMESTAMP = block.timestamp + 7 days;
    uint256 DEFAULT_VESTING_END_TIMESTAMP = block.timestamp + 12 days;

    // effectively a "beforeEach" block
    function setUp() public {
        // Deploy
        treasuryVesterFactory = new TreasuryVesterFactory(IERC20(lon));

        // Mint 10k tokens to this contract
        lon.mint(address(this), 10000 * 1e18);

        // Label addresses for easier debugging
        vm.label(recipient, "Recipient");
        vm.label(address(this), "TestingContract");
        vm.label(address(treasuryVesterFactory), "TreasuryVesterFactoryContract");
        vm.label(address(treasuryVester), "TreasuryVesterContract");
    }

    /***************************************************
     *                Test: createVester               *
     ***************************************************/

    function testCannotCreateVesterWithZeroAmount() public {
        uint256 invalidVestingAmount = 0;
        vm.expectRevert("vesting amount is zero");
        treasuryVesterFactory.createVester(
            recipient,
            invalidVestingAmount,
            DEFAULT_VESTING_BEGIN_TIMESTAMP,
            DEFAULT_VESTING_CLIFF_TIMESTAMP,
            DEFAULT_VESTING_END_TIMESTAMP
        );
    }

    function testCannotCreateVesterWithInvalidBeginTimestamp() public {
        uint256 invalidVestingBeginTimestamp = block.timestamp - 1;
        vm.expectRevert("vesting begin too early");
        treasuryVesterFactory.createVester(
            recipient,
            DEFAULT_VESTING_AMOUNT,
            invalidVestingBeginTimestamp,
            DEFAULT_VESTING_CLIFF_TIMESTAMP,
            DEFAULT_VESTING_END_TIMESTAMP
        );
    }

    function testCannotCreateVesterWithInvalidCliffTimestamp() public {
        uint256 invalidVestingCliffTimestamp = DEFAULT_VESTING_BEGIN_TIMESTAMP - 1;
        vm.expectRevert("cliff is too early");
        treasuryVesterFactory.createVester(
            recipient,
            DEFAULT_VESTING_AMOUNT,
            DEFAULT_VESTING_BEGIN_TIMESTAMP,
            invalidVestingCliffTimestamp,
            DEFAULT_VESTING_END_TIMESTAMP
        );
    }

    function testCannotCreateVesterWithInvalidEndTimestamp() public {
        uint256 invalidVestingEndTimestamp = DEFAULT_VESTING_CLIFF_TIMESTAMP - 1;
        vm.expectRevert("end is too early");
        treasuryVesterFactory.createVester(
            recipient,
            DEFAULT_VESTING_AMOUNT,
            DEFAULT_VESTING_BEGIN_TIMESTAMP,
            DEFAULT_VESTING_CLIFF_TIMESTAMP,
            invalidVestingEndTimestamp
        );
    }

    function testCannotCreateVesterWithoutApproval() public {
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        treasuryVesterFactory.createVester(
            recipient,
            DEFAULT_VESTING_AMOUNT,
            DEFAULT_VESTING_BEGIN_TIMESTAMP,
            DEFAULT_VESTING_CLIFF_TIMESTAMP,
            DEFAULT_VESTING_END_TIMESTAMP
        );
    }

    function testCreateVester() public {
        lon.approve(address(treasuryVesterFactory), DEFAULT_VESTING_AMOUNT);
        vm.expectEmit(
            false, // We do not check the deployed Vester address as it's deterministic generated and irrelevant to correctness
            true,
            false,
            true
        );
        emit VesterCreated(
            address(this), // We do not check the deployed Vester address as it's deterministic generated and irrelevant to correctness
            recipient,
            DEFAULT_VESTING_AMOUNT
        );
        treasuryVester = TreasuryVester(
            treasuryVesterFactory.createVester(
                recipient,
                DEFAULT_VESTING_AMOUNT,
                DEFAULT_VESTING_BEGIN_TIMESTAMP,
                DEFAULT_VESTING_CLIFF_TIMESTAMP,
                DEFAULT_VESTING_END_TIMESTAMP
            )
        );
        assertEq(treasuryVester.lon(), address(lon));
        assertEq(treasuryVester.recipient(), recipient);
        assertEq(treasuryVester.vestingAmount(), DEFAULT_VESTING_AMOUNT);
        assertEq(treasuryVester.vestingBegin(), DEFAULT_VESTING_BEGIN_TIMESTAMP);
        assertEq(treasuryVester.vestingCliff(), DEFAULT_VESTING_CLIFF_TIMESTAMP);
        assertEq(treasuryVester.lastUpdate(), DEFAULT_VESTING_BEGIN_TIMESTAMP);
    }

    /*********************************************************
     *              Test: set Vester recipient               *
     *********************************************************/

    function _createVesterWithDefaultValues() internal returns (TreasuryVester) {
        return
            TreasuryVester(
                treasuryVesterFactory.createVester(
                    recipient,
                    DEFAULT_VESTING_AMOUNT,
                    DEFAULT_VESTING_BEGIN_TIMESTAMP,
                    DEFAULT_VESTING_CLIFF_TIMESTAMP,
                    DEFAULT_VESTING_END_TIMESTAMP
                )
            );
    }

    function testCannotSetRecipientByNotRecipient() public {
        lon.approve(address(treasuryVesterFactory), DEFAULT_VESTING_AMOUNT);
        treasuryVester = _createVesterWithDefaultValues();
        vm.expectRevert("unauthorized");
        vm.prank(other);
        treasuryVester.setRecipient(other);
    }

    function _getVestedAmount(
        uint256 vestingAmount,
        uint256 lastUpdate,
        uint256 beginTimestamp,
        uint256 endTimestamp
    ) internal view returns (uint256) {
        return vestingAmount.mul(block.timestamp - lastUpdate).div(endTimestamp.sub(beginTimestamp));
    }

    function testVested() public {
        lon.approve(address(treasuryVesterFactory), DEFAULT_VESTING_AMOUNT);
        treasuryVester = _createVesterWithDefaultValues();

        vm.warp(DEFAULT_VESTING_CLIFF_TIMESTAMP - 1);
        assertEq(treasuryVester.vested(), 0);

        vm.warp(DEFAULT_VESTING_CLIFF_TIMESTAMP + 1 days);
        assertEq(
            treasuryVester.vested(),
            _getVestedAmount(DEFAULT_VESTING_AMOUNT, DEFAULT_VESTING_BEGIN_TIMESTAMP, DEFAULT_VESTING_BEGIN_TIMESTAMP, DEFAULT_VESTING_END_TIMESTAMP)
        );

        vm.warp(DEFAULT_VESTING_END_TIMESTAMP);
        assertEq(treasuryVester.vested(), DEFAULT_VESTING_AMOUNT);
    }

    function testCannotClaimBeforeCliff() public {
        lon.approve(address(treasuryVesterFactory), DEFAULT_VESTING_AMOUNT);
        treasuryVester = _createVesterWithDefaultValues();
        vm.expectRevert("not time yet");
        treasuryVester.claim();
    }

    function testClaimMultipleTimes() public {
        lon.approve(address(treasuryVesterFactory), DEFAULT_VESTING_AMOUNT);
        treasuryVester = _createVesterWithDefaultValues();

        // Claim right after cliff
        vm.warp(DEFAULT_VESTING_CLIFF_TIMESTAMP);
        BalanceSnapshot.Snapshot memory recipientLon = BalanceSnapshot.take(recipient, address(lon));
        uint256 expectedClaimAmount = _getVestedAmount(
            DEFAULT_VESTING_AMOUNT,
            DEFAULT_VESTING_BEGIN_TIMESTAMP,
            DEFAULT_VESTING_BEGIN_TIMESTAMP,
            DEFAULT_VESTING_END_TIMESTAMP
        );
        treasuryVester.claim();
        recipientLon.assertChange(int256(expectedClaimAmount));
        uint256 lastUpdate = block.timestamp;
        assertEq(treasuryVester.lastUpdate(), lastUpdate);

        // Claim after cliff but before end
        vm.warp(DEFAULT_VESTING_CLIFF_TIMESTAMP + 1 days);
        recipientLon = BalanceSnapshot.take(recipient, address(lon));
        expectedClaimAmount = _getVestedAmount(DEFAULT_VESTING_AMOUNT, lastUpdate, DEFAULT_VESTING_BEGIN_TIMESTAMP, DEFAULT_VESTING_END_TIMESTAMP);
        treasuryVester.claim();
        recipientLon.assertChange(int256(expectedClaimAmount));
        lastUpdate = block.timestamp;
        assertEq(treasuryVester.lastUpdate(), lastUpdate);

        // Claim after end
        vm.warp(DEFAULT_VESTING_END_TIMESTAMP);
        recipientLon = BalanceSnapshot.take(recipient, address(lon));
        expectedClaimAmount = lon.balanceOf(address(treasuryVester));
        treasuryVester.claim();
        recipientLon.assertChange(int256(expectedClaimAmount));
        assertEq(lon.balanceOf(address(treasuryVester)), 0);
    }

    function testClaimAllAtOnce() public {
        lon.approve(address(treasuryVesterFactory), DEFAULT_VESTING_AMOUNT);
        treasuryVester = _createVesterWithDefaultValues();

        // Claim after end
        vm.warp(DEFAULT_VESTING_END_TIMESTAMP);
        BalanceSnapshot.Snapshot memory recipientLon = BalanceSnapshot.take(recipient, address(lon));
        uint256 expectedClaimAmount = lon.balanceOf(address(treasuryVester));
        treasuryVester.claim();
        recipientLon.assertChange(int256(expectedClaimAmount));
        assertEq(lon.balanceOf(address(treasuryVester)), 0);
    }
}
