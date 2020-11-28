pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "./mock/MockTreasury.sol";
import "./DebtPopperRewards.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}
contract AccountingEngine {
    mapping (uint256 => address) public debtPoppers;

    function popDebt(uint256 timestamp) external {
        debtPoppers[timestamp] = msg.sender;
    }
}

contract DebtPopperRewardsTest is DSTest {
    Hevm hevm;

    DebtPopperRewards popperRewards;
    AccountingEngine accountingEngine;
    MockTreasury treasury;

    DSToken systemCoin;

    uint256 popReward         = 5E18;
    uint256 coinsToMint       = 1E40;
    uint256 interPeriodDelay  = 1 weeks;
    uint256 rewardTimeline    = 100 days;
    uint256 maxPeriodRewards  = 5;
    uint256 rewardStartTime   = now + 1 weeks;
    uint256 rewardPeriodStart = now + 2 weeks;

    uint RAY = 10 ** 27;
    uint WAD = 10 ** 18;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        systemCoin       = new DSToken("RAI", "RAI");
        accountingEngine = new AccountingEngine();
        treasury         = new MockTreasury(address(systemCoin));
        popperRewards    = new DebtPopperRewards(
            address(accountingEngine),
            address(treasury),
            rewardPeriodStart,
            interPeriodDelay,
            rewardTimeline,
            popReward,
            maxPeriodRewards,
            rewardStartTime
        );

        systemCoin.mint(address(treasury), coinsToMint);

        treasury.setTotalAllowance(address(popperRewards), uint(-1));
        treasury.setPerBlockAllowance(address(popperRewards), popReward);
    }

    function test_setup() public {
        assertEq(popperRewards.authorizedAccounts(address(this)), 1);
        assertTrue(address(popperRewards.accountingEngine()) == address(accountingEngine));
        assertTrue(address(popperRewards.treasury()) == address(treasury));
        assertEq(popperRewards.rewardPeriodStart(), rewardPeriodStart);
        assertEq(popperRewards.interPeriodDelay(), interPeriodDelay);
        assertEq(popperRewards.rewardTimeline(), rewardTimeline);
        assertEq(popperRewards.popReward(), popReward);
        assertEq(popperRewards.maxPeriodRewards(), maxPeriodRewards);
        assertEq(popperRewards.rewardStartTime(), rewardStartTime);
    }
    /* function testFail_get_reward_before_rewardPeriodStart() public {

    }
    function testFail_get_reward_before_rewardStartTime() public {

    } */

}
