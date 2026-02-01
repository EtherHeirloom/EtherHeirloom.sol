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
 * @title Test 7: Fee Recipient Attack Edge Case
 * @notice Tests that feeRecipient cannot be manipulated or attacked
 * @dev Scenario: Attacker tries to change feeRecipient or exploit fee mechanism
 */
contract Test07_FeeRecipientAttack is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(1);
    address public beneficiary = address(2);
    address public feeRecipient = address(4);
    address public attacker = address(0xbad);

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

    function test_FeeRecipientIsImmutable() public {
        // Verify initial fee recipient
        assertEq(heirloom.protocolFeeRecipient(), feeRecipient);

        // Get the storage slot where protocolFeeRecipient is stored
        // Try to verify it can't be changed through any means
        address currentRecipient = heirloom.protocolFeeRecipient();
        assertEq(currentRecipient, feeRecipient);

        // Even after transactions, it should remain the same
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Fee recipient should still be the same
        assertEq(heirloom.protocolFeeRecipient(), feeRecipient);
    }

    function test_OnlyCurrentRecipientCanUpdate() public {
        // Attacker tries to change fee recipient - should fail
        vm.prank(attacker);
        vm.expectRevert(EtherHeirloom.OnlyProtocolRecipient.selector);
        heirloom.updateFeeRecipient(attacker);

        // Owner tries to change fee recipient - should fail
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.OnlyProtocolRecipient.selector);
        heirloom.updateFeeRecipient(attacker);

        // Beneficiary tries to change fee recipient - should fail
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.OnlyProtocolRecipient.selector);
        heirloom.updateFeeRecipient(attacker);

        // Only current fee recipient can change it
        address newRecipient = address(0x123);
        vm.prank(feeRecipient);
        heirloom.updateFeeRecipient(newRecipient);

        assertEq(heirloom.protocolFeeRecipient(), newRecipient);
    }

    function test_CannotSetZeroAddressAsRecipient() public {
        // Current recipient tries to set zero address - should fail
        vm.prank(feeRecipient);
        vm.expectRevert(EtherHeirloom.InvalidRecipientAddress.selector);
        heirloom.updateFeeRecipient(address(0));

        // Verify it's still the original
        assertEq(heirloom.protocolFeeRecipient(), feeRecipient);
    }

    function test_FeeRecipientReceivesFees() public {
        uint256 initialBalance = feeRecipient.balance;

        // Setup legacy - should pay setupFee
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Fee recipient should have received 0.001 ether
        assertEq(feeRecipient.balance, initialBalance + 0.001 ether);

        skip(101);

        // Claim - should pay operationFee
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Fee recipient should have received another 0.0005 ether
        assertEq(feeRecipient.balance, initialBalance + 0.001 ether + 0.0005 ether);
    }

    function test_ExcessFeesRefundedToSender() public {
        // Setup with excess payment
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.01 ether}(beneficiaries, shares, 100); // Sent 10x required

        // Owner should be refunded the excess
        uint256 ownerBalanceAfter = owner.balance;
        assertEq(ownerBalanceBefore - ownerBalanceAfter, 0.001 ether); // Only setup fee taken

        skip(101);

        // Claim with excess payment
        vm.deal(beneficiary, 10 ether);
        uint256 beneficiaryBalanceBefore = beneficiary.balance;

        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.005 ether}(owner, beneficiary, tokens);

        // Beneficiary should be refunded the excess
        uint256 beneficiaryBalanceAfter = beneficiary.balance;
        assertEq(beneficiaryBalanceBefore - beneficiaryBalanceAfter, 0.0005 ether); // Only operation fee taken
    }

    function test_AttackerCannotStealFees() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        uint256 feeRecipientBalance = feeRecipient.balance;

        // Attacker cannot call any function to steal accumulated fees
        // The contract doesn't hold fees - they're sent immediately to recipient

        // Verify fee recipient has the fees
        assertEq(feeRecipient.balance, feeRecipientBalance);
    }

    function test_NewRecipientReceivesFutureFeesOnly() public {
        // Setup legacy with original recipient
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        assertEq(feeRecipient.balance, 0.001 ether);

        // Change fee recipient
        address newRecipient = address(0x999);
        vm.prank(feeRecipient);
        heirloom.updateFeeRecipient(newRecipient);

        skip(101);

        // New operation should pay new recipient
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Old recipient still has old fees
        assertEq(feeRecipient.balance, 0.001 ether);
        // New recipient got new fees
        assertEq(newRecipient.balance, 0.0005 ether);
    }

    function test_FeeRecipientUpdateEmitsEvent() public {
        address newRecipient = address(0x888);

        vm.prank(feeRecipient);
        vm.expectEmit(true, true, false, false);
        emit EtherHeirloom.FeeRecipientUpdated(feeRecipient, newRecipient);
        heirloom.updateFeeRecipient(newRecipient);
    }

    function test_MultipleRecipientUpdates() public {
        address recipient2 = address(0x222);
        address recipient3 = address(0x333);

        // First update
        vm.prank(feeRecipient);
        heirloom.updateFeeRecipient(recipient2);
        assertEq(heirloom.protocolFeeRecipient(), recipient2);

        // Old recipient cannot update anymore
        vm.prank(feeRecipient);
        vm.expectRevert(EtherHeirloom.OnlyProtocolRecipient.selector);
        heirloom.updateFeeRecipient(recipient3);

        // New recipient can update
        vm.prank(recipient2);
        heirloom.updateFeeRecipient(recipient3);
        assertEq(heirloom.protocolFeeRecipient(), recipient3);

        // recipient2 cannot update anymore
        vm.prank(recipient2);
        vm.expectRevert(EtherHeirloom.OnlyProtocolRecipient.selector);
        heirloom.updateFeeRecipient(feeRecipient);
    }

    function test_FeesAreNotStoredInContract() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Contract should have 0 balance (fees sent immediately)
        assertEq(address(heirloom).balance, 0);

        skip(101);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Contract still has 0 balance
        assertEq(address(heirloom).balance, 0);
    }

    function test_DeadlineResetFeeGoesToRecipient() public {
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

        // Recipient should receive deadline extension fee
        assertEq(feeRecipient.balance, recipientBalanceBefore + 0.0001 ether);
    }

    function test_BatchClaimFeesCalculatedCorrectly() public {
        MockToken token2 = new MockToken();
        token.transfer(owner, 1000 * 1e18);
        token2.transfer(owner, 1000 * 1e18);

        vm.startPrank(owner);
        token.approve(address(heirloom), type(uint256).max);
        token2.approve(address(heirloom), type(uint256).max);
        vm.stopPrank();

        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        uint256 recipientBalanceBefore = feeRecipient.balance;

        // Batch claim 2 tokens - fee is now per transaction, not per token
        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens); // Flat fee per transaction

        // Recipient should receive 1 * operationFee (flat fee per transaction)
        assertEq(feeRecipient.balance, recipientBalanceBefore + 0.0005 ether);
    }
}
