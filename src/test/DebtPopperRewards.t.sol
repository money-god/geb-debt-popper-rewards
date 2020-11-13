pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./mock/MockTreasury.sol";
import "./DebtPopperRewards.sol";

contract AccountingEngine {
    mapping (uint256 => address) public debtPoppers;

    function popDebt(uint256 timestamp) external {
        debtPoppers[timestamp] = msg.sender;
    }
}

contract DebtPopperRewardsTest is DSTest {
    DebtPopperRewards popperRewards;
    AccountingEngine accountingEngine;
    MockTreasury treasury;

    function setUp() public {
        popperRewards = new DebtPopperRewards();
    }


}
