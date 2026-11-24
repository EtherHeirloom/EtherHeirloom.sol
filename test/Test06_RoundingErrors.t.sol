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
 * @title Test 6: Mathematical Precision and Rounding Errors Edge Case
 * @notice Tests that division and percentage calculations don't cause issues
 * @dev Scenario: Tests with small amounts, odd percentages (33.33%), and precision edge cases
 */
contract Test06_RoundingErrors is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(1);
    address public beneficiary1 = address(2);
    address public beneficiary2 = address(3);
    address public beneficiary3 = address(5);
    address public feeRecipient = address(4);

    function setUp() public {
        heirloom = new EtherHeirloom(
            feeRecipient,
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );
        token = new MockToken();

        // Owner approves unlimited
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    function test_ThreeWaySplit_ThirdsRounding() public {
        // Transfer small amount to owner
        token.transfer(owner, 100);

        // Setup: 33.33%, 33.33%, 33.34% (3333, 3333, 3334 basis points)
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 3334; // 33.34%
        shares[1] = 3333; // 33.33%
        shares[2] = 3333; // 33.33%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims: 100 * 3334 / 10000 = 33.34 = 33 (truncated)
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 33);

        // B2 claims: (100-33) * 3333 / 10000... but virtual pool calculation:
        // virtualPool = 67 + 33 = 100
        // due = 100 * 3333 / 10000 = 33
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 33);

        // B3 claims the remainder
        // virtualPool = 34 + 66 = 100
        // due = 100 * 3333 / 10000 = 33.33 = 33
        vm.deal(beneficiary3, 10 ether);
        vm.prank(beneficiary3);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary3, tokens);
        assertEq(token.balanceOf(beneficiary3), 33);

        // Check that owner still has 1 wei due to rounding
        assertEq(token.balanceOf(owner), 1);
    }

    function test_VerySmallAmount_OneWei() public {
        // Transfer only 1 wei to owner
        token.transfer(owner, 1);

        // Setup 50/50 split
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims: 1 * 5000 / 10000 = 0.5 = 0 (truncated)
        // Should revert when payment rounds to 0
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // Should remain 0
        assertEq(token.balanceOf(beneficiary1), 0);
    }

    function test_VerySmallAmount_TwoWei() public {
        // Transfer only 2 wei to owner
        token.transfer(owner, 2);

        // Setup 50/50 split
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims: 2 * 5000 / 10000 = 1
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 1);

        // B2 claims: virtualPool = 1 + 1 = 2, due = 2 * 5000 / 10000 = 1
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 1);

        // All distributed correctly
        assertEq(token.balanceOf(owner), 0);
    }

    function test_VeryLargeAmount() public {
        // Transfer large amount to owner (within mock token supply)
        uint256 largeAmount = 100000 * 1e18; // 100k tokens
        token.transfer(owner, largeAmount);

        // Setup 33.33%, 33.33%, 33.34% split
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 3333;
        shares[1] = 3333;
        shares[2] = 3334;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // B1 gets 33330 (due to claim order and virtual pool)
        assertEq(token.balanceOf(beneficiary1), 33330 * 1e18);

        // B2 claims
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 33330 * 1e18);

        // B3 claims
        vm.deal(beneficiary3, 10 ether);
        vm.prank(beneficiary3);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary3, tokens);
        assertEq(token.balanceOf(beneficiary3), 33340 * 1e18);

        // Total distributed: 33330 + 33330 + 33340 = 100000
        // Verify no overflow or precision loss
        assertEq(
            token.balanceOf(beneficiary1) + token.balanceOf(beneficiary2) + token.balanceOf(beneficiary3),
            100000 * 1e18
        );
    }

    function test_OddPercentages_PrimesSum() public {
        // Transfer 10000 wei for easy calculation
        token.transfer(owner, 10000);

        // Setup odd percentages that sum to 100%: 23%, 37%, 40%
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 4000; // 40%
        shares[1] = 3700; // 37%
        shares[2] = 2300; // 23%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 4000); // 40% of 10000

        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 3700); // 37% of 10000

        vm.deal(beneficiary3, 10 ether);
        vm.prank(beneficiary3);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary3, tokens);
        assertEq(token.balanceOf(beneficiary3), 2300); // 23% of 10000

        // Perfect distribution
        assertEq(token.balanceOf(owner), 0);
    }

    function test_RoundingWithRefill() public {
        // Start with 99 wei (odd number)
        token.transfer(owner, 99);

        // Setup 50/50 split
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000;
        shares[1] = 5000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims: 99 * 5000 / 10000 = 49.5 = 49
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 49);

        // B2 claims: virtualPool = 50 + 49 = 99, due = 49
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 49);

        // Owner has 1 wei left due to rounding
        assertEq(token.balanceOf(owner), 1);

        // Refill with 1 more wei
        token.transfer(owner, 1);

        // Now virtualPool = 2 + 98 = 100
        // B1 due = 100 * 5000 / 10000 = 50, claimed = 49, new = 1
        vm.prank(beneficiary1);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 50);

        // B2 due = 100 * 5000 / 10000 = 50, claimed = 49, new = 1
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 50);

        // Perfect split after refill
        assertEq(token.balanceOf(owner), 0);
    }

    function test_OneHundredPercentSingleBeneficiary() public {
        // Test that 100% is calculated correctly
        token.transfer(owner, 12345);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // Should get exact amount with no rounding loss
        assertEq(token.balanceOf(beneficiary1), 12345);
        assertEq(token.balanceOf(owner), 0);
    }

    function test_MinimumShareOnePercent() public {
        // Test 1% share (100 basis points)
        token.transfer(owner, 10000);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 100;   // 1%
        shares[1] = 9900;  // 99%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 100); // 1% of 10000

        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 9900); // 99% of 10000
    }

    function test_VirtualPoolRoundingConsistency() public {
        // Test that virtual pool calculation is consistent across multiple claims
        token.transfer(owner, 1000);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 3334;
        shares[1] = 3333;
        shares[2] = 3333;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // All claim sequentially
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        uint256 b1Amount = token.balanceOf(beneficiary1);

        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        uint256 b2Amount = token.balanceOf(beneficiary2);

        vm.deal(beneficiary3, 10 ether);
        vm.prank(beneficiary3);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary3, tokens);
        uint256 b3Amount = token.balanceOf(beneficiary3);

        // Verify virtual pool kept consistency
        uint256 totalClaimed = b1Amount + b2Amount + b3Amount;
        assertLe(token.balanceOf(owner), 1); // At most 1 wei left due to rounding
        assertGe(totalClaimed, 999); // At least 999 claimed
        assertLe(totalClaimed, 1000); // At most 1000 claimed
    }
}
