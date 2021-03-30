pragma solidity 0.6.7;

import {Feed, GebDeployTestBase, EnglishCollateralAuctionHouse} from "geb-deploy/test/GebDeploy.t.base.sol";
import "../DebtPopperRewards.sol";

abstract contract WethLike {
    function balanceOf(address) virtual public view returns (uint);
    function approve(address, uint) virtual public;
    function transfer(address, uint) virtual public;
    function transferFrom(address, address, uint) virtual public;
    function deposit() virtual public payable;
    function withdraw(uint) virtual public;
}

contract Attacker {
    function doGetRewardForPop(address popperRewards, uint256 slotTimestamp, address feeReceiver) public {
        DebtPopperRewards(popperRewards).getRewardForPop(slotTimestamp, feeReceiver);
    }
}

contract DebtPopperRewardsIntegrationTest is GebDeployTestBase {

    Attacker attacker;

    DebtPopperRewards popperRewards;

    uint256 fixedReward         = 5E18;
    uint256 coinsToMint       = 1E40;
    uint256 interPeriodDelay  = 1 weeks;
    uint256 rewardTimeline    = 100 days;
    uint256 maxPeriodRewards  = 50E18;

    uint RAY = 10 ** 27;

    function addAuthorization(address dst, address who) public {
        DebtPopperRewards(dst).addAuthorization(who);
    }

    function setUp() override public {
        super.setUp();

        deployIndexWithCreatorPermissions(bytes32("ENGLISH"));

        popperRewards    = new DebtPopperRewards(
            address(accountingEngine),
            address(stabilityFeeTreasury),
            now + 2 weeks,
            interPeriodDelay,
            rewardTimeline,
            fixedReward,
            maxPeriodRewards,
            now + 1 weeks
        );
        attacker         = new Attacker();

        // generating coin to feed StabilityFeeTreasury
        WethLike(address(ethJoin.collateral())).deposit{value: 100 ether}();
        WethLike(address(ethJoin.collateral())).approve(address(ethJoin), 100 ether);
        ethJoin.join(address(this), 100 ether);
        safeEngine.modifySAFECollateralization(
            "ETH",
            address(this),
            address(this),
            address(this),
            100 ether,
            1000 ether
        );
        safeEngine.approveSAFEModification(address(coinJoin));
        coinJoin.exit(address(stabilityFeeTreasury), 1000 ether);

        // auth in stabilityFeeTreasury
        address      usr = address(this);
        bytes32      tag;  assembly { tag := extcodehash(usr) }
        bytes memory fax = abi.encodeWithSignature("addAuthorization(address,address)", address(stabilityFeeTreasury), address(this));
        uint         eta = now;
        pause.scheduleTransaction(usr, tag, fax, eta);
        pause.executeTransaction(usr, tag, fax, eta);

        // setting allowances
        stabilityFeeTreasury.setTotalAllowance(address(popperRewards), uint(-1));
        stabilityFeeTreasury.setPerBlockAllowance(address(popperRewards), fixedReward * 10E27);
    }

    function test_setup() public {
        assertEq(popperRewards.authorizedAccounts(address(this)), 1);
        assertTrue(address(popperRewards.accountingEngine()) == address(accountingEngine));
        assertTrue(address(popperRewards.treasury()) == address(stabilityFeeTreasury));
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
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(popTime);
        popperRewards.modifyParameters("rewardPeriodStart", newPeriodStart);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(popTime, address(0));
    }
    function testFail_slot_from_future() public {
        hevm.warp(now + 2 weeks + 1);
        hevm.warp(now + 5);
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(now);
        popperRewards.getRewardForPop(now, address(0));
    }
    function testFail_get_reward_after_timeline_passed() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now + popperRewards.rewardTimeline() + 1);
        popperRewards.getRewardForPop(slotTime, address(0));
    }
    function testFail_get_reward_non_popper() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now + 1);
        attacker.doGetRewardForPop(address(popperRewards), slotTime, address(0));
    }
    function testFail_get_twice_reward_same_slot() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
    function testFail_get_reward_above_max_period_rewards() public {
        popperRewards.modifyParameters("maxPeriodRewards", fixedReward);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now+15);
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime + 15);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
        popperRewards.getRewardForPop(slotTime + 15, address(0x123));
    }
    function testFail_get_reward_when_total_allowance_zero() public {
        stabilityFeeTreasury.setTotalAllowance(address(popperRewards), 0);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
    function testFail_get_reward_per_block_allowance_zero() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(popperRewards), 0);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
    function test_getRewardForPop() public {
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));

        assertEq(safeEngine.coinBalance(address(0x123)), fixedReward * 10**27);
        assertTrue(popperRewards.rewardedPop(slotTime));
        assertEq(popperRewards.rewardsPerPeriod(popperRewards.rewardPeriodStart()), fixedReward);
    }
    function test_getRewardForPop_gas() public {
        hevm.warp(now + 2 weeks + 1);
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(now);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(now - 1, address(this));
    }
    function test_getRewardForPop_gas_multiple() public {
        hevm.warp(now + 2 weeks + 1);
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(now);
        hevm.warp(now + 1);
        uint gas;
        for (uint i = 0; i < 10; i++) {
            gas = gasleft();
            popperRewards.getRewardForPop(now - 1, address(this));
            emit log_named_uint("gas", gas -gasleft());
            accountingEngine.pushDebtToQueue(100 ether);
            accountingEngine.popDebtFromQueue(now);
            hevm.warp(now + 1);
        }
    }
    function test_getRewardForPop_after_rewardPeriodStart_updated2() public {
        popperRewards.modifyParameters("maxPeriodRewards", fixedReward);
        hevm.warp(now + 2 weeks + 1);
        uint slotTime = now;
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);
        hevm.warp(now + 15);
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime + 15);
        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
        hevm.warp(popperRewards.rewardPeriodStart());
        popperRewards.getRewardForPop(slotTime + 15, address(0x123));

        assertEq(safeEngine.coinBalance(address(0x123)), fixedReward * 2 * 10**27);
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
        accountingEngine.pushDebtToQueue(100 ether);
        accountingEngine.popDebtFromQueue(slotTime);

        hevm.warp(now + 1);
        popperRewards.getRewardForPop(slotTime, address(0x123));
    }
}
