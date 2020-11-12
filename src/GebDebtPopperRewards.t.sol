pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebDebtPopperRewards.sol";

contract GebDebtPopperRewardsTest is DSTest {
    GebDebtPopperRewards rewards;

    function setUp() public {
        rewards = new GebDebtPopperRewards();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
