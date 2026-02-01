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
 * @title Test 1: Zero Balance Edge Case
 * @notice Tests that claiming with zero balance reverts with ClaimFailed
 * @dev Scenario: Owner sets up legacy with 100% share, but has 0 tokens at claim time
 */
contract Test01_ZeroBalance is Test {
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

        // Owner approves contract but has no tokens
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    function test_ZeroBalanceNonStrictMode() public {
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

        // Beneficiary tries to claim using batch - should revert when no tokens transferred
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        // Should revert with ClaimFailed when no tokens were transferred
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }

    function test_ZeroBalanceAfterTransfer() public {
        // Transfer tokens to owner first
        token.transfer(owner, 1000 * 1e18);

        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Advance time past deadline
        skip(101);

        // Owner transfers all tokens away before beneficiary claims
        vm.prank(owner);
        token.transfer(address(0xdead), 1000 * 1e18);

        // Now balance is zero
        assertEq(token.balanceOf(owner), 0);

        // Beneficiary tries to claim - should revert when no tokens transferred
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        
        // Should revert with ClaimFailed when no tokens were transferred
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }
}
