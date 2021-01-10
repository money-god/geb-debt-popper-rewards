pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "./mock/MockTreasury.sol";
import "../DebtPopperRewards.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}
contract AccountingEngine {
    mapping (uint256 => address) public debtPoppers;

    function popDebt(uint256 timestamp) external {
        debtPoppers[timestamp] = msg.sender;
    }
}
contract Attacker {
    function doGetRewardForPop(address popperRewards, uint256 slotTimestamp, address feeReceiver) public {
        DebtPopperRewards(popperRewards).getRewardForPop(slotTimestamp, feeReceiver);
    }
}

contract DebtPopperRewardsTest is DSTest {
    Hevm hevm;

    Attacker attacker;

    DebtPopperRewards popperRewards;
    AccountingEngine accountingEngine;
    MockTreasury treasury;

    DSToken systemCoin;

    uint256 fixedReward         = 5E18;
    uint256 coinsToMint       = 1E40;
    uint256 interPeriodDelay  = 1 weeks;
    uint256 rewardTimeline    = 100 days;
    uint256 maxPeriodRewards  = 50E18;

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
            now + 2 weeks,
            interPeriodDelay,
            rewardTimeline,
            fixedReward,
            maxPeriodRewards,
            now + 1 weeks
        );
        attacker         = new Attacker();

        systemCoin.mint(address(treasury), coinsToMint);

        treasury.setTotalAllowance(address(popperRewards), uint(-1));
        treasury.setPerBlockAllowance(address(popperRewards), fixedReward * 10E27);
    }

    function test_setup() public {
        assertEq(popperRewards.authorizedAccounts(address(this)), 1);
        assertTrue(address(popperRewards.accountingEngine()) == address(accountingEngine));
        assertTrue(address(popperRewards.treasury()) == address(treasury));
        assertEq(popperRewards.rewardPeriodStart(), now + 2 weeks);
        assertEq(popperRewards.interPeriodDelay(), interPeriodDelay);
        assertEq(popperRewards.rewardTimeline(), rewardTimeline);
        assertEq(popperRewards.fixedReward(), fixedReward);
        assertEq(popperRewards.maxPeriodRewards(), maxPeriodRewards);
        assertEq(popperRewards.rewardStartTime(), now + 1 weeks);
    }
    function testFail_get_reward_before_rewardStartTime() public {
        hevm.warp(now + 2 weeks + 1);
        uint256 newPeriodStart = now + 5;
        uint256 popTime = now;
        accountingEngine.popDebt(popTime);
        popperRewards.modifyParameters("rewardPeriodStart", newPeriodStart);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(popTime, address(0));
    }
    function testFail_slot_from_future() public {
        hevm.warp(now + 2 weeks + 1);
        accountingEngine.popDebt(now + 5);
        popperRewards.getRewardForPop(now + 5, address(0));
    }
    function testFail_get_reward_after_timeline_passed() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        hevm.warp(now + popperRewards.rewardTimeline() + 1);
        popperRewards.getRewardForPop(slotTime, address(0));
    }
    function testFail_get_reward_non_popper() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        hevm.warp(now + 1);
        attacker.doGetRewardForPop(address(popperRewards), slotTime, address(0));
    }
    function testFail_get_twice_reward_same_slot() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
    function testFail_get_reward_above_max_period_rewards() public {
        popperRewards.modifyParameters("maxPeriodRewards", fixedReward);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        accountingEngine.popDebt(slotTime + 15);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
        popperRewards.getRewardForPop(slotTime + 15, address(0x123));
    }
    function testFail_get_reward_when_total_allowance_zero() public {
        treasury.setTotalAllowance(address(popperRewards), 0);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
    function testFail_get_reward_per_block_allowance_zero() public {
        treasury.setPerBlockAllowance(address(popperRewards), 0);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
    function test_getRewardForPop() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));

        assertEq(systemCoin.balanceOf(address(0x123)), fixedReward);
        assertTrue(popperRewards.rewardedPop(slotTime));
        assertEq(popperRewards.rewardsPerPeriod(popperRewards.rewardPeriodStart()), fixedReward);
    }
    function test_getRewardForPop_after_rewardPeriodStart_updated() public {
        popperRewards.modifyParameters("maxPeriodRewards", fixedReward);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);
        accountingEngine.popDebt(slotTime + 15);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
        hevm.warp(popperRewards.rewardPeriodStart());
        popperRewards.getRewardForPop(slotTime + 15, address(0x123));

        assertEq(systemCoin.balanceOf(address(0x123)), fixedReward * 2);
        assertTrue(popperRewards.rewardedPop(slotTime));
        assertTrue(popperRewards.rewardedPop(slotTime + 15));
        assertEq(popperRewards.rewardsPerPeriod(popperRewards.rewardPeriodStart()), 0);
        assertTrue(popperRewards.rewardPeriodStart() > now);
    }
    function testFail_getReward_after_disable() public {
        popperRewards.disableContract();
        popperRewards.modifyParameters("maxPeriodRewards", fixedReward);

        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.popDebt(slotTime);

        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
}
