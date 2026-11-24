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
 * @title Test 10: Deadline Reset (Proof of Life) Edge Case
 * @notice Tests that owner can reset deadline at any time to prove they're alive
 * @dev Scenario: Owner calls resetHeirloom at various times including right before deadline
 */
contract Test10_DeadlineReset is Test {
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

    function test_ResetOneSecondBeforeDeadline() public {
        // Setup legacy with 100 second delay
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

        // New deadline should be 100 seconds from current time
        assertEq(newDeadline, block.timestamp + 100);
        assertGt(newDeadline, originalDeadline);

        // Beneficiary tries to claim at original deadline - should fail
        vm.warp(originalDeadline);
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Move to new deadline
        vm.warp(newDeadline);

        // Now claim should work
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_ResetImmediatelyAfterSetup() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 originalDeadline = heirloom.ownerExecutionTimestamp(owner);

        // Reset immediately
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(200);

        uint256 newDeadline = heirloom.ownerExecutionTimestamp(owner);

        // New deadline should be 200 seconds from now
        assertEq(newDeadline, block.timestamp + 200);
        assertGt(newDeadline, originalDeadline);
    }

    function test_ResetAfterDeadlinePassed() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 originalDeadline = heirloom.ownerExecutionTimestamp(owner);

        // Move past the deadline
        vm.warp(originalDeadline + 50);

        // Beneficiary could claim now, but owner is still alive
        // Owner resets deadline
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        uint256 newDeadline = heirloom.ownerExecutionTimestamp(owner);

        // New deadline is from current time
        assertEq(newDeadline, block.timestamp + 100);

        // Beneficiary cannot claim anymore (deadline extended)
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }

    function test_MultipleResets() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 deadline1 = heirloom.ownerExecutionTimestamp(owner);

        // Skip 30 seconds and reset
        skip(30);
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);
        uint256 deadline2 = heirloom.ownerExecutionTimestamp(owner);
        assertEq(deadline2, block.timestamp + 100);

        // Skip another 40 seconds and reset again
        skip(40);
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(150);
        uint256 deadline3 = heirloom.ownerExecutionTimestamp(owner);
        assertEq(deadline3, block.timestamp + 150);

        // Skip another 60 seconds and reset again
        skip(60);
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(200);
        uint256 deadline4 = heirloom.ownerExecutionTimestamp(owner);
        assertEq(deadline4, block.timestamp + 200);

        // Each deadline should be later than the previous
        assertGt(deadline2, deadline1);
        assertGt(deadline3, deadline2);
        assertGt(deadline4, deadline3);
    }

    function test_ResetWithInsufficientFee() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Try to reset with insufficient fee
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherHeirloom.InsufficientFee.selector, 0.0001 ether, 0.00001 ether));
        heirloom.resetDeadline{value: 0.00001 ether}(100);
    }

    function test_ResetWithExcessFeeRefunded() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 ownerBalanceBefore = owner.balance;

        // Reset with excess fee
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.001 ether}(100); // 10x required

        uint256 ownerBalanceAfter = owner.balance;

        // Only extension fee should be deducted
        assertEq(ownerBalanceBefore - ownerBalanceAfter, 0.0001 ether);
    }

    function test_ResetEmitsEvent() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(50);

        // Expect event emission
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit EtherHeirloom.DeadlineReset(owner, block.timestamp + 200);
        heirloom.resetDeadline{value: 0.0001 ether}(200);
    }

    function test_NonOwnerCannotReset() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 originalOwnerDeadline = heirloom.ownerExecutionTimestamp(owner);

        // Beneficiary resets their own deadline (not owner's)
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        // Beneficiary has their own deadline now
        uint256 beneficiaryDeadline = heirloom.ownerExecutionTimestamp(beneficiary);
        assertEq(beneficiaryDeadline, block.timestamp + 100);

        // Owner's deadline unchanged
        uint256 ownerDeadline = heirloom.ownerExecutionTimestamp(owner);
        assertEq(ownerDeadline, originalOwnerDeadline);
    }

    function test_ResetToZeroDelay() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(50);

        // Reset to zero delay (immediate execution)
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(0);

        uint256 newDeadline = heirloom.ownerExecutionTimestamp(owner);
        assertEq(newDeadline, block.timestamp);

        // Beneficiary can claim immediately
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_ResetToVeryLongDelay() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Reset to 10 years
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(365 days * 10);

        uint256 newDeadline = heirloom.ownerExecutionTimestamp(owner);
        assertEq(newDeadline, block.timestamp + 365 days * 10);

        // Beneficiary cannot claim for 10 years
        skip(365 days * 10 - 1);
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }

    function test_ResetAfterPartialClaim() public {
        // Setup two beneficiaries
        address beneficiary2 = address(0x103);
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Beneficiary 1 claims
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 500 * 1e18);

        // Owner resets deadline before beneficiary2 claims
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        // Beneficiary 2 cannot claim immediately anymore
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);

        // Skip to new deadline
        skip(101);

        // Now beneficiary2 can claim
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 500 * 1e18);
    }

    function test_ResetDoesNotAffectClaimedAmounts() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Beneficiary claims
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);

        // Owner resets deadline
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        // Owner receives more tokens
        token.transfer(owner, 500 * 1e18);

        skip(101);

        // Beneficiary claims new tokens
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1500 * 1e18);

        // Virtual pool calculation should still work correctly
        assertEq(heirloom.ownerTokenReleased(owner, address(token)), 1500 * 1e18);
        assertEq(heirloom.beneficiaryClaims(owner, beneficiary, address(token)), 1500 * 1e18);
    }

    function test_FeeRecipientReceivesResetFees() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 recipientBalanceBefore = feeRecipient.balance;

        // Reset deadline
        vm.prank(owner);
        heirloom.resetDeadline{value: 0.0001 ether}(100);

        // Fee recipient should receive the fee
        assertEq(feeRecipient.balance, recipientBalanceBefore + 0.0001 ether);
    }
}
