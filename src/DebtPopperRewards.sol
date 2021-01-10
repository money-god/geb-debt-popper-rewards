pragma solidity 0.6.7;

abstract contract AccountingEngineLike {
    function debtPoppers(uint256) virtual public view returns (address);
}

contract DebtPopperRewards {
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
        uint256 popReward_,
        uint256 maxPeriodRewards_,
        uint256 rewardStartTime_
    ) public {
        require(rewardPeriodStart_ >= now, "DebtPopperRewards/invalid-reward-period-start");
        require(interPeriodDelay_ > 0, "DebtPopperRewards/invalid-inter-period-delay");
        require(rewardTimeline_ > 0, "DebtPopperRewards/invalid-harvest-timeline");
        require(popReward_ > 0, "DebtPopperRewards/invalid-pop-reward");
        require(both(maxPeriodRewards_ > 0, maxPeriodRewards_ % popReward_ == 0), "DebtPopperRewards/invalid-max-period-rewards");
        require(accountingEngine_ != address(0), "DebtPopperRewards/null-accounting-engine");

        authorizedAccounts[msg.sender] = 1;
        contractEnabled                = 1;

        accountingEngine   = AccountingEngineLike(accountingEngine_);
        treasury           = StabilityFeeTreasuryLike(treasury_);

        rewardPeriodStart  = rewardPeriodStart_;
        interPeriodDelay   = interPeriodDelay_;
        rewardTimeline     = rewardTimeline_;
        popReward          = popReward_;
        maxPeriodRewards   = maxPeriodRewards_;
        rewardStartTime    = rewardStartTime_;

        emit ModifyParameters("accountingEngine", accountingEngine_);
        emit ModifyParameters("treasury", treasury_);
        emit ModifyParameters("interPeriodDelay", interPeriodDelay);
        emit ModifyParameters("rewardTimeline", rewardTimeline);
        emit ModifyParameters("popReward", popReward);
        emit ModifyParameters("rewardStartTime", rewardStartTime);
        emit ModifyParameters("maxPeriodRewards", maxPeriodRewards);

        emit SetRewardPeriodStart(rewardPeriodStart);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
      assembly{ z := and(x, y)}
    }
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        require(val > 0, "DebtPopperRewards/invalid-value");
        if (parameter == "interPeriodDelay") {
          interPeriodDelay = val;
        }
        else if (parameter == "rewardTimeline") {
          rewardTimeline = val;
        }
        else if (parameter == "popReward") {
          require(maxPeriodRewards % val == 0, "DebtPopperRewards/invalid-pop-reward");
          popReward = val;
        }
        else if (parameter == "maxPeriodRewards") {
          require(val % popReward == 0, "DebtPopperRewards/invalid-max-period-rewards");
          maxPeriodRewards = val;
        }
        else if (parameter == "rewardPeriodStart") {
          require(val > now, "DebtPopperRewards/invalid-reward-period-start");
          rewardPeriodStart = val;
        }
        else revert("DebtPopperRewards/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "DebtPopperRewards/null-address");
        if (parameter == "treasury") treasury = StabilityFeeTreasuryLike(addr);
        else revert("DebtPopperRewards/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }

    function disableContract() external isAuthorized {
        contractEnabled = 0;
        emit DisableContract();
    }

    // --- Math ---
    uint internal constant WAD      = 10 ** 18;
    uint internal constant RAY      = 10 ** 27;
    function minimum(uint x, uint y) internal pure returns (uint z) {
        z = (x <= y) ? x : y;
    }
    function addition(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    // --- Treasury Utils ---
    function treasuryAllowance() public view returns (uint256) {
        (uint total, uint perBlock) = treasury.getAllowance(address(this));
        return minimum(total, perBlock);
    }
    function getCallerReward() public view returns (uint256 reward) {
        reward = minimum(popReward, treasuryAllowance() / RAY);
    }
    function rewardCaller(address proposedFeeReceiver) internal {
        require(address(treasury) != proposedFeeReceiver, "DebtPopperRewards/reward-receiver-cannot-be-treasury");
        require(both(address(treasury) != address(0), popReward > 0), "DebtPopperRewards/invalid-treasury-or-reward");
        address finalFeeReceiver = (proposedFeeReceiver == address(0)) ? msg.sender : proposedFeeReceiver;
        treasury.pullFunds(finalFeeReceiver, treasury.systemCoin(), popReward);
        emit RewardCaller(finalFeeReceiver, popReward);
    }

    function getRewardForPop(uint256 slotTimestamp, address feeReceiver) external {
        require(contractEnabled == 1, "DebtPopperRewards/contract-disabled");
        require(slotTimestamp >= rewardStartTime, "DebtPopperRewards/slot-time-before-reward-start");
        require(slotTimestamp < now, "DebtPopperRewards/slot-cannot-be-in-the-future");
        require(now >= rewardPeriodStart, "DebtPopperRewards/wait-more");
        require(addition(slotTimestamp, rewardTimeline) >= now, "DebtPopperRewards/missed-reward-window");
        require(accountingEngine.debtPoppers(slotTimestamp) == msg.sender, "DebtPopperRewards/not-debt-popper");
        require(!rewardedPop[slotTimestamp], "DebtPopperRewards/pop-already-rewarded");
        require(getCallerReward() >= popReward, "DebtPopperRewards/invalid-available-reward");

        rewardedPop[slotTimestamp]          = true;
        rewardsPerPeriod[rewardPeriodStart] = addition(rewardsPerPeriod[rewardPeriodStart], popReward);

        if (rewardsPerPeriod[rewardPeriodStart] >= maxPeriodRewards) {
          rewardPeriodStart = addition(now, interPeriodDelay);
          emit SetRewardPeriodStart(rewardPeriodStart);
        }

        emit RewardForPop(slotTimestamp, popReward);

        // Give the reward
        rewardCaller(feeReceiver);
    }
}
