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
 * @title Test 3: Wallet Refill (Virtual Pool) Edge Case
 * @notice Tests that beneficiaries can claim new tokens after wallet refills
 * @dev Scenario: Beneficiary claims their share, owner receives more tokens (dividends), beneficiary claims again
 */
contract Test03_WalletRefill is Test {
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

        // Transfer 1000 tokens to owner
        token.transfer(owner, 1000 * 1e18);

        // Owner approves unlimited
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    function test_RefillAfterFullClaim() public {
        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Advance time past deadline
        skip(101);

        // Beneficiary claims all 1000 tokens
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
        assertEq(token.balanceOf(owner), 0);

        // Try to claim again - should revert
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Owner receives 500 more tokens (dividends/income)
        token.transfer(owner, 500 * 1e18);

        // Virtual pool is now: 500 (current) + 1000 (released) = 1500
        // Payment due: 1500 * 100% = 1500
        // Already claimed: 1000
        // New payment: 1500 - 1000 = 500
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1500 * 1e18);
        assertEq(token.balanceOf(owner), 0);
    }

    function test_MultipleRefills() public {
        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Initial claim: 1000 tokens
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);

        // Refill #1: 300 tokens
        token.transfer(owner, 300 * 1e18);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1300 * 1e18);

        // Refill #2: 150 tokens
        token.transfer(owner, 150 * 1e18);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1450 * 1e18);

        // Refill #3: 1000 tokens
        token.transfer(owner, 1000 * 1e18);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 2450 * 1e18);
    }

    function test_RefillWithPartialShare() public {
        // Setup legacy with 50% allocation
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary;
        beneficiaries[1] = address(0x99);

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Initial claim: 50% of 1000 = 500 tokens
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 500 * 1e18);
        assertEq(token.balanceOf(owner), 500 * 1e18);

        // Refill: 400 tokens (owner now has 900)
        token.transfer(owner, 400 * 1e18);

        // Virtual pool: 900 (current) + 500 (released) = 1400
        // Payment due: 1400 * 50% = 700
        // Already claimed: 500
        // New payment: 700 - 500 = 200
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 700 * 1e18);
        assertEq(token.balanceOf(owner), 700 * 1e18);
    }

    function test_RefillWithMultipleBeneficiaries() public {
        address beneficiary2 = address(0x103);

        // Setup legacy: B1=50%, B2=50%
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

        // B1 claims: 50% of 1000 = 500 tokens
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 500 * 1e18);

        // B2 claims: 50% of 1000 = 500 tokens
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 500 * 1e18);

        // Owner has 0 left
        assertEq(token.balanceOf(owner), 0);

        // Refill: 400 tokens
        token.transfer(owner, 400 * 1e18);

        // B1 virtual pool: 400 + 1000 = 1400, due: 700, claimed: 500, new: 200
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 700 * 1e18); // 500 + 200

        // B2 virtual pool: 200 + 1200 = 1400, due: 700, claimed: 500, new: 200
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 700 * 1e18); // 500 + 200

        // Owner has 0 left (all 400 distributed: 200 to B1, 200 to B2)
        assertEq(token.balanceOf(owner), 0);
    }

    function test_RefillWithZeroInitialBalance() public {
        // Owner transfers all tokens away first
        vm.prank(owner);
        token.transfer(address(0xdead), 1000 * 1e18);

        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Try to claim with zero balance - should revert
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Now owner receives tokens (first income)
        token.transfer(owner, 750 * 1e18);

        // Beneficiary can now claim
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 750 * 1e18);
    }

    function test_PartialRefillDueToAllowance() public {
        // Owner approves only 100 tokens
        vm.prank(owner);
        token.approve(address(heirloom), 100 * 1e18);

        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Claim limited by allowance: only 100 tokens
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 100 * 1e18);

        // Owner receives 500 more tokens (now has 1400 total)
        token.transfer(owner, 500 * 1e18);

        // But still only has 0 allowance left - should revert
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Owner increases allowance by 300 more
        vm.prank(owner);
        token.approve(address(heirloom), 300 * 1e18);

        // Now can claim: virtual pool 1400 + 100 = 1500, due 1500, claimed 100, ideal 1400, allowance 300
        // Payment: min(300, 1400) = 300
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 400 * 1e18);
    }
}
