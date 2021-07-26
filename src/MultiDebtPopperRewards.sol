pragma solidity 0.6.7;

import "geb-treasury-reimbursement/reimbursement/multi/MultiMandatoryFixedTreasuryReimbursement.sol";

abstract contract AccountingEngineLike {
    function debtPoppers(bytes32, uint256) virtual public view returns (address);
}

contract MultiDebtPopperRewards is MultiMandatoryFixedTreasuryReimbursement {
    // --- Variables ---
    // When the next reward period starts
    uint256 public rewardPeriodStart;                    // [unix timestamp]
    // Delay between two consecutive reward periods
    uint256 public interPeriodDelay;                     // [seconds]
    // Time (after a block of debt is popped) after which no reward can be given anymore
    uint256 public rewardTimeline;                       // [seconds]
    // Amount of pops that can be rewarded per period
    uint256 public maxPerPeriodPops;
    // Timestamp from which the contract accepts requests for rewarding debt poppers
    uint256 public rewardStartTime;

    // Whether a debt block has been popped
    mapping(uint256 => bool)    public rewardedPop;      // [unix timestamp => bool]
    // Amount of pops that were rewarded in each period
    mapping(uint256 => uint256) public rewardsPerPeriod; // [unix timestamp => wad]

    // Accounting engine contract
    AccountingEngineLike        public accountingEngine;

    // --- Events ---
    event SetRewardPeriodStart(uint256 rewardPeriodStart);
    event RewardForPop(uint256 slotTimestamp, uint256 reward);

    constructor(
        bytes32 coinName_,
        address accountingEngine_,
        address treasury_,
        uint256 rewardPeriodStart_,
        uint256 interPeriodDelay_,
        uint256 rewardTimeline_,
        uint256 fixedReward_,
        uint256 maxPerPeriodPops_,
        uint256 rewardStartTime_
    ) public MultiMandatoryFixedTreasuryReimbursement(coinName_, treasury_, fixedReward_) {
        require(rewardPeriodStart_ >= now, "MultiDebtPopperRewards/invalid-reward-period-start");
        require(interPeriodDelay_ > 0, "MultiDebtPopperRewards/invalid-inter-period-delay");
        require(rewardTimeline_ > 0, "MultiDebtPopperRewards/invalid-harvest-timeline");
        require(maxPerPeriodPops_ > 0, "MultiDebtPopperRewards/invalid-max-per-period-pops");
        require(accountingEngine_ != address(0), "MultiDebtPopperRewards/null-accounting-engine");

        accountingEngine   = AccountingEngineLike(accountingEngine_);

        rewardPeriodStart  = rewardPeriodStart_;
        interPeriodDelay   = interPeriodDelay_;
        rewardTimeline     = rewardTimeline_;
        fixedReward        = fixedReward_;
        maxPerPeriodPops   = maxPerPeriodPops_;
        rewardStartTime    = rewardStartTime_;

        emit ModifyParameters("accountingEngine", accountingEngine_);
        emit ModifyParameters("interPeriodDelay", interPeriodDelay);
        emit ModifyParameters("rewardTimeline", rewardTimeline);
        emit ModifyParameters("rewardStartTime", rewardStartTime);
        emit ModifyParameters("maxPerPeriodPops", maxPerPeriodPops);

        emit SetRewardPeriodStart(rewardPeriodStart);
    }

    // --- Administration ---
    /*
    * @notify Modify a uint256 parameter
    * @param parameter The parameter name
    * @param val The new value for the parameter
    */
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        require(val > 0, "MultiDebtPopperRewards/invalid-value");
        if (parameter == "interPeriodDelay") {
          interPeriodDelay = val;
        }
        else if (parameter == "rewardTimeline") {
          rewardTimeline = val;
        }
        else if (parameter == "fixedReward") {
          require(val > 0, "MultiDebtPopperRewards/null-reward");
          fixedReward = val;
        }
        else if (parameter == "maxPerPeriodPops") {
          maxPerPeriodPops = val;
        }
        else if (parameter == "rewardPeriodStart") {
          require(val > now, "MultiDebtPopperRewards/invalid-reward-period-start");
          rewardPeriodStart = val;
        }
        else revert("MultiDebtPopperRewards/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }
    /*
    * @notify Set a new treasury address
    * @param parameter The parameter name
    * @param addr The new address for the parameter
    */
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "MultiDebtPopperRewards/null-address");
        if (parameter == "treasury") treasury = StabilityFeeTreasuryLike(addr);
        else revert("MultiDebtPopperRewards/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }

    /*
    * @notify Get rewarded for popping a debt slot from the AccountingEngine debt queue
    * @oaran slotTimestamp The time of the popped slot
    * @param feeReceiver The address that will receive the reward for popping
    */
    function getRewardForPop(uint256 slotTimestamp, address feeReceiver) external {
        // Perform checks
        require(slotTimestamp >= rewardStartTime, "MultiDebtPopperRewards/slot-time-before-reward-start");
        require(slotTimestamp < now, "MultiDebtPopperRewards/slot-cannot-be-in-the-future");
        require(now >= rewardPeriodStart, "MultiDebtPopperRewards/wait-more");
        require(addition(slotTimestamp, rewardTimeline) >= now, "MultiDebtPopperRewards/missed-reward-window");
        require(accountingEngine.debtPoppers(coinName, slotTimestamp) == msg.sender, "MultiDebtPopperRewards/not-debt-popper");
        require(!rewardedPop[slotTimestamp], "MultiDebtPopperRewards/pop-already-rewarded");
        require(getCallerReward() >= fixedReward, "MultiDebtPopperRewards/invalid-available-reward");

        // Update state
        rewardedPop[slotTimestamp]          = true;
        rewardsPerPeriod[rewardPeriodStart] = addition(rewardsPerPeriod[rewardPeriodStart], 1);

        // If we offered rewards for too many pops, enforce a delay since rewards are available again
        if (rewardsPerPeriod[rewardPeriodStart] >= maxPerPeriodPops) {
          rewardPeriodStart = addition(now, interPeriodDelay);
          emit SetRewardPeriodStart(rewardPeriodStart);
        }

        emit RewardForPop(slotTimestamp, fixedReward);

        // Give the reward
        rewardCaller(feeReceiver);
    }
}
