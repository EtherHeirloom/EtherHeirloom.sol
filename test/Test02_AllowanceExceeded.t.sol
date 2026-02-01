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
 * @title Test 2: Allowance Exceeded Edge Case
 * @notice Tests that contract handles insufficient allowance gracefully
 * @dev Scenario: Owner has 1000 tokens, 100% share, but only approves 50 tokens
 */
contract Test02_AllowanceExceeded is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(1);
    address public beneficiary = address(2);
    address public feeRecipient = address(4);

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
    }

    function test_AllowanceLimit() public {
        // Owner approves only 50 tokens despite having 1000
        vm.prank(owner);
        token.approve(address(heirloom), 50 * 1e18);

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

        // Beneficiary claims - should only get 50 tokens (the allowance limit)
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Assert beneficiary received only what was allowed
        assertEq(token.balanceOf(beneficiary), 50 * 1e18);

        // Assert owner still has 950 tokens
        assertEq(token.balanceOf(owner), 950 * 1e18);
    }

    function test_AllowanceIncreaseLater() public {
        // Owner approves only 50 tokens initially
        vm.prank(owner);
        token.approve(address(heirloom), 50 * 1e18);

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

        // First claim - gets 50 tokens
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 50 * 1e18);

        // Owner increases allowance to 500 tokens total
        vm.prank(owner);
        token.approve(address(heirloom), 500 * 1e18);

        // Beneficiary claims again - should get remaining up to allowance
        // Virtual pool: 950 (current) + 50 (released) = 1000
        // Payment due: 1000 * 100% = 1000
        // Already claimed: 50
        // Ideal payment: 950
        // Available: min(950 balance, 500 allowance) = 500
        // Payment: min(500, 950) = 500
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 550 * 1e18);

        // Owner still has 450 tokens
        assertEq(token.balanceOf(owner), 450 * 1e18);
    }

    function test_AllowanceFullyUsedThenIncreased() public {
        // Owner approves 300 tokens
        vm.prank(owner);
        token.approve(address(heirloom), 300 * 1e18);

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

        // Claim all allowed tokens
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 300 * 1e18);

        // Try to claim again - should revert when allowance is 0
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Owner increases allowance
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);

        // Now beneficiary can claim the rest
        // Virtual pool: 700 (current) + 300 (released) = 1000
        // Payment due: 1000 * 100% = 1000
        // Already claimed: 300
        // Ideal payment: 700
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18);
        assertEq(token.balanceOf(owner), 0);
    }

    function test_PartialShareWithLimitedAllowance() public {
        // Owner approves 200 tokens
        vm.prank(owner);
        token.approve(address(heirloom), 200 * 1e18);

        // Setup legacy with 50% allocation
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary;
        beneficiaries[1] = address(0x99); // Second beneficiary to make total 100%

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Advance time past deadline
        skip(101);

        // Virtual pool: 1000
        // Payment due: 1000 * 50% = 500
        // Available: min(1000 balance, 200 allowance) = 200
        // Payment: min(200, 500) = 200
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
        assertEq(token.balanceOf(beneficiary), 200 * 1e18);

        // Verify beneficiaryClaims is updated correctly
        assertEq(heirloom.beneficiaryClaims(owner, beneficiary, address(token)), 200 * 1e18);

        // Verify ownerTokenReleased is updated correctly
        assertEq(heirloom.ownerTokenReleased(owner, address(token)), 200 * 1e18);
    }

    function test_RevertWhenAvailableIsZero() public {
        // Owner has tokens but zero allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Try to claim - should revert when allowance is 0
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }
}
