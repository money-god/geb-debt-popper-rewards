pragma solidity 0.6.7;

import "geb-treasury-reimbursement/MandatoryFixedTreasuryReimbursement.sol";

abstract contract AccountingEngineLike {
    function debtPoppers(uint256) virtual public view returns (address);
}

contract DebtPopperRewards is MandatoryFixedTreasuryReimbursement {
    // --- Variables ---
    // When the next reward period starts
    uint256 public rewardPeriodStart;                    // [unix timestamp]
    // Delay between two consecutive reward periods
    uint256 public interPeriodDelay;                     // [seconds]
    // Time (after a block of debt is popped) after which no reward can be given anymore
    uint256 public rewardTimeline;                       // [seconds]
    // Total amount of rewards that can be distributed per period
    uint256 public maxPeriodRewards;                     // [wad]
    // Timestamp from which the contract accepts requests to reward poppers
    uint256 public rewardStartTime;
    // Flag indicating whether the contract is active
    uint256 public contractEnabled;

    // Whether a debt block has been popped
    mapping(uint256 => bool)    public rewardedPop;         // [unix timestamp => bool]
    // Amount of rewards given in a period
    mapping(uint256 => uint256) public rewardsPerPeriod; // [unix timestamp => wad]

    AccountingEngineLike        public accountingEngine;

    // --- Events ---
    event SetRewardPeriodStart(uint256 rewardPeriodStart);
    event RewardForPop(uint256 slotTimestamp, uint256 reward);
    event DisableContract();

    constructor(
        address accountingEngine_,
        address treasury_,
        uint256 rewardPeriodStart_,
        uint256 interPeriodDelay_,
        uint256 rewardTimeline_,
        uint256 fixedReward_,
        uint256 maxPeriodRewards_,
        uint256 rewardStartTime_
    ) public MandatoryFixedTreasuryReimbursement(treasury_, fixedReward_) {
        require(rewardPeriodStart_ >= now, "DebtPopperRewards/invalid-reward-period-start");
        require(interPeriodDelay_ > 0, "DebtPopperRewards/invalid-inter-period-delay");
        require(rewardTimeline_ > 0, "DebtPopperRewards/invalid-harvest-timeline");
        require(both(maxPeriodRewards_ > 0, maxPeriodRewards_ % fixedReward_ == 0), "DebtPopperRewards/invalid-max-period-rewards");
        require(accountingEngine_ != address(0), "DebtPopperRewards/null-accounting-engine");

        contractEnabled    = 1;
        accountingEngine   = AccountingEngineLike(accountingEngine_);

        rewardPeriodStart  = rewardPeriodStart_;
        interPeriodDelay   = interPeriodDelay_;
        rewardTimeline     = rewardTimeline_;
        fixedReward        = fixedReward_;
        maxPeriodRewards   = maxPeriodRewards_;
        rewardStartTime    = rewardStartTime_;

        emit ModifyParameters("accountingEngine", accountingEngine_);
        emit ModifyParameters("interPeriodDelay", interPeriodDelay);
        emit ModifyParameters("rewardTimeline", rewardTimeline);
        emit ModifyParameters("rewardStartTime", rewardStartTime);
        emit ModifyParameters("maxPeriodRewards", maxPeriodRewards);

        emit SetRewardPeriodStart(rewardPeriodStart);
    }

    // --- Administration ---
    /*
    * @notify Modify a uint256 parameter
    * @param parameter The parameter name
    * @param val The new value for the parameter
    */
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        require(val > 0, "DebtPopperRewards/invalid-value");
        if (parameter == "interPeriodDelay") {
          interPeriodDelay = val;
        }
        else if (parameter == "rewardTimeline") {
          rewardTimeline = val;
        }
        else if (parameter == "fixedReward") {
          require(maxPeriodRewards % val == 0, "DebtPopperRewards/invalid-fixed-reward");
          fixedReward = val;
        }
        else if (parameter == "maxPeriodRewards") {
          require(val % fixedReward == 0, "DebtPopperRewards/invalid-max-period-rewards");
          maxPeriodRewards = val;
        }
        else if (parameter == "rewardPeriodStart") {
          require(val > now, "DebtPopperRewards/invalid-reward-period-start");
          rewardPeriodStart = val;
        }
        else revert("DebtPopperRewards/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }
    /*
    * @notify Set a new treasury address
    * @param parameter The parameter name
    * @param addr The new address for the parameter
    */
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "DebtPopperRewards/null-address");
        if (parameter == "treasury") treasury = StabilityFeeTreasuryLike(addr);
        else revert("DebtPopperRewards/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }

    /*
    * @notify Disable this contract and forbid getRewardForPop calls
    */
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        emit DisableContract();
    }

    /*
    * @notify Get rewarded for popping a debt slot from the AccountingEngine debt queue
    * @oaran slotTimestamp The time of the popped slot
    * @param feeReceiver The address that will receive the reward for popping
    */
    function getRewardForPop(uint256 slotTimestamp, address feeReceiver) external {
        require(contractEnabled == 1, "DebtPopperRewards/contract-disabled");
        require(slotTimestamp >= rewardStartTime, "DebtPopperRewards/slot-time-before-reward-start");
        require(slotTimestamp < now, "DebtPopperRewards/slot-cannot-be-in-the-future");
        require(now >= rewardPeriodStart, "DebtPopperRewards/wait-more");
        require(addition(slotTimestamp, rewardTimeline) >= now, "DebtPopperRewards/missed-reward-window");
        require(accountingEngine.debtPoppers(slotTimestamp) == msg.sender, "DebtPopperRewards/not-debt-popper");
        require(!rewardedPop[slotTimestamp], "DebtPopperRewards/pop-already-rewarded");
        require(getCallerReward() >= fixedReward, "DebtPopperRewards/invalid-available-reward");

        rewardedPop[slotTimestamp]          = true;
        rewardsPerPeriod[rewardPeriodStart] = addition(rewardsPerPeriod[rewardPeriodStart], fixedReward);

        if (rewardsPerPeriod[rewardPeriodStart] >= maxPeriodRewards) {
          rewardPeriodStart = addition(now, interPeriodDelay);
          emit SetRewardPeriodStart(rewardPeriodStart);
        }

        emit RewardForPop(slotTimestamp, fixedReward);

        // Give the reward
        rewardCaller(feeReceiver);
    }
}
