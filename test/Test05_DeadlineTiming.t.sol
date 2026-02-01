// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/EtherHeirloom.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1000000 * 1e18);
    }
}

/**
 * @title Test 5: Deadline Timing Edge Case (Race Condition)
 * @notice Tests boundary conditions around deadline execution
 * @dev Scenario: Tests exact deadline timing to prevent off-by-one errors
 */
contract Test05_DeadlineTiming is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(0x101);
    address public beneficiary = address(0x102);
    address public feeRecipient = address(0x104);

    function setUp() public {
        heirloom = new EtherHeirloom(
            feeRecipient,
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );
        token = new MockToken();

        // Transfer tokens to owner
        token.transfer(owner, 1000 * 1e18);

        // Owner approves unlimited
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    function test_ClaimExactlyAtDeadline() public {
        // Setup with 100 second delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 deadline = heirloom.ownerExecutionTimestamp(owner);

        // Move to exactly the deadline timestamp
        vm.warp(deadline);

        // Should be able to claim exactly at deadline (>= check)
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_ClaimOneSecondBeforeDeadline() public {
        // Setup with 100 second delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 deadline = heirloom.ownerExecutionTimestamp(owner);

        // Move to 1 second before deadline
        vm.warp(deadline - 1);

        // Should NOT be able to claim
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }

    function test_ClaimOneSecondAfterDeadline() public {
        // Setup with 100 second delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 deadline = heirloom.ownerExecutionTimestamp(owner);

        // Move to 1 second after deadline
        vm.warp(deadline + 1);

        // Should be able to claim
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_ResetDeadlineOneSecondBefore() public {
        // Setup with 100 second delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 originalDeadline = heirloom.ownerExecutionTimestamp(owner);

        // Move to 1 second before deadline
        vm.warp(originalDeadline - 1);

        // Owner resets deadline (proof of life)
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        uint256 newDeadline = heirloom.ownerExecutionTimestamp(owner);

        // New deadline should be 100 seconds from now (not original time)
        assertEq(newDeadline, block.timestamp + 100);

        // Beneficiary tries to claim at old deadline time - should fail
        vm.warp(originalDeadline);
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Move to new deadline
        vm.warp(newDeadline);

        // Now should work
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_ResetDeadlineAtExactDeadline() public {
        // Setup with 100 second delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 originalDeadline = heirloom.ownerExecutionTimestamp(owner);

        // Move to exactly the deadline
        vm.warp(originalDeadline);

        // Owner can still reset (proof they're alive)
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        uint256 newDeadline = heirloom.ownerExecutionTimestamp(owner);
        assertEq(newDeadline, originalDeadline + 100);
    }

    function test_ResetDeadlineAfterDeadline() public {
        // Setup with 100 second delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 originalDeadline = heirloom.ownerExecutionTimestamp(owner);

        // Move past the deadline
        vm.warp(originalDeadline + 50);

        // Owner can still reset even after deadline passed
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        uint256 newDeadline = heirloom.ownerExecutionTimestamp(owner);

        // New deadline is from current time, not original
        assertEq(newDeadline, originalDeadline + 50 + 100);

        // Beneficiary tries to claim at old deadline + 50 - should fail
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }

    function test_MultipleDeadlineResets() public {
        // Setup with 100 second delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 deadline1 = heirloom.ownerExecutionTimestamp(owner);
        uint256 startTime = block.timestamp;
        assertEq(deadline1, startTime + 100);

        // Skip 50 seconds
        skip(50);

        // Reset #1
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);
        uint256 deadline2 = heirloom.ownerExecutionTimestamp(owner);
        assertEq(deadline2, startTime + 50 + 100);

        // Skip another 50 seconds
        skip(50);

        // Reset #2
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(200);
        uint256 deadline3 = heirloom.ownerExecutionTimestamp(owner);
        assertEq(deadline3, startTime + 50 + 50 + 200);

        // Try to claim before final deadline
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Move to final deadline
        vm.warp(deadline3);

        // Should work now
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_ZeroDelayDeadline() public {
        // Setup with 0 second delay (immediate execution)
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 0);

        uint256 deadline = heirloom.ownerExecutionTimestamp(owner);

        // Deadline should be current timestamp
        assertEq(deadline, block.timestamp);

        // Should be able to claim immediately
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_VeryLongDelay() public {
        // Setup with 1 year delay
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 365 days);

        // Try to claim before 1 year - should fail
        skip(365 days - 1);
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Skip final second
        skip(1);

        // Should work now
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_DeadlineDoesNotAffectMultipleBeneficiaries() public {
        // Setup with 2 beneficiaries
        address beneficiary2 = address(0x103);
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 6000; // 60%
        shares[1] = 4000; // 40%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 deadline = heirloom.ownerExecutionTimestamp(owner);

        // Both beneficiaries share the same deadline
        vm.warp(deadline - 1);

        // Neither can claim yet
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);

        // Move to deadline
        vm.warp(deadline);

        // Both can claim now
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 600 * 1e18);

        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 400 * 1e18);
    }
}
