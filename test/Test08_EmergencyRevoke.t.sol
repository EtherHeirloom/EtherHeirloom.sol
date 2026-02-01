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
 * @title Test 8: Emergency Revoke Edge Case
 * @notice Tests that owner can revoke allowances and beneficiary cannot force withdrawals
 * @dev Scenario: Owner calls approve(0) on USDC and removes legacy entries
 */
contract Test08_EmergencyRevoke is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(0x101);
    address public beneficiary1 = address(0x102);
    address public beneficiary2 = address(0x103);
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

        // Owner approves unlimited initially
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    function _getLegacy(address _owner, address _beneficiary) internal view returns (EtherHeirloom.LegacyAccount memory) {
        EtherHeirloom.LegacyAccount[] memory ownerLegacies = heirloom.getHeirloomsByOwner(_owner, 0, 50);
        for (uint256 i = 0; i < ownerLegacies.length; i++) {
            if (ownerLegacies[i].beneficiary == _beneficiary) {
                return ownerLegacies[i];
            }
        }
        EtherHeirloom.LegacyAccount memory empty;
        return empty;
    }

    function test_RevokeAllowanceBeforeClaim() public {
        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Owner revokes allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Advance time past deadline
        skip(101);

        // Beneficiary tries to claim - should revert when no allowance
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // Verify no tokens were transferred
        assertEq(token.balanceOf(beneficiary1), 0);
        assertEq(token.balanceOf(owner), 1000 * 1e18);
    }

    function test_RevokeAllowanceInBatchMode() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Owner revokes allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        skip(101);

        // Batch claim should revert when no tokens transferred
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // No tokens transferred
        assertEq(token.balanceOf(beneficiary1), 0);
    }

    function test_PartialRevokeAllowance() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Owner reduces allowance to 100 tokens
        vm.prank(owner);
        token.approve(address(heirloom), 100 * 1e18);

        skip(101);

        // Beneficiary claims - should only get 100 tokens
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        assertEq(token.balanceOf(beneficiary1), 100 * 1e18);
        assertEq(token.balanceOf(owner), 900 * 1e18);
    }

    function test_RevokeAfterPartialClaim() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Owner approves only 300 tokens
        vm.prank(owner);
        token.approve(address(heirloom), 300 * 1e18);

        // Beneficiary claims 300 tokens
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 300 * 1e18);

        // Owner revokes remaining allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Beneficiary tries to claim remaining - should revert when no allowance
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // Balance unchanged (no transfer because reverted)
        assertEq(token.balanceOf(beneficiary1), 300 * 1e18);
    }

    function test_RevokeAndRestoreAllowance() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Owner revokes allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Beneficiary cannot claim - should revert when no allowance
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // Owner restores allowance
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);

        // Now beneficiary can claim
        vm.prank(beneficiary1);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 1000 * 1e18);
    }

    function test_RevokeForSpecificBeneficiary() public {
        // Setup two beneficiaries
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

        // Owner revokes entire allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Neither beneficiary can claim - should revert when no allowance
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
    }

    function test_RevokeAndDeactivateLegacy() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Owner revokes allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Owner also removes beneficiary from legacy
        address[] memory emptyBeneficiaries = new address[](1);
        emptyBeneficiaries[0] = beneficiary2; // Replace with different beneficiary
        uint16[] memory emptyShares = new uint16[](1);
        emptyShares[0] = 10000;

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(emptyBeneficiaries, emptyShares, 100);

        // Original beneficiary cannot claim (legacy not active anymore)
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.LegacyNotActive.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // Verify legacy is inactive for beneficiary1
        bool isActive = _getLegacy(owner, beneficiary1).isActive;
        assertEq(isActive, false);
    }

    function test_ContractCannotForceTransfer() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Owner revokes allowance
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Verify contract has no special permission to take tokens
        assertEq(token.allowance(owner, address(heirloom)), 0);

        // Beneficiary claim should revert when no tokens transferred
        vm.deal(beneficiary1, 10 ether);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // No tokens moved
        assertEq(token.balanceOf(beneficiary1), 0);
        assertEq(token.balanceOf(owner), 1000 * 1e18);
    }

    function test_AllowanceCheckBeforeTransfer() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Set very small allowance
        vm.prank(owner);
        token.approve(address(heirloom), 1); // Only 1 wei

        // Claim should only transfer 1 wei
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        assertEq(token.balanceOf(beneficiary1), 1);
        assertEq(token.balanceOf(owner), 1000 * 1e18 - 1);
    }

    function test_MultipleTokensPartialRevoke() public {
        MockToken token2 = new MockToken();
        token2.transfer(owner, 1000 * 1e18);

        // Approve both tokens
        vm.startPrank(owner);
        token.approve(address(heirloom), type(uint256).max);
        token2.approve(address(heirloom), type(uint256).max);
        vm.stopPrank();

        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Revoke allowance for token1 only
        vm.prank(owner);
        token.approve(address(heirloom), 0);

        // Batch claim both tokens
        vm.deal(beneficiary1, 10 ether);
        address[] memory tokens = new address[](2);
        tokens[0] = address(token);
        tokens[1] = address(token2);

        vm.prank(beneficiary1);
        heirloom.claimLegacies{value: 0.001 ether}(owner, beneficiary1, tokens);

        // Token1 not transferred, token2 transferred
        assertEq(token.balanceOf(beneficiary1), 0);
        assertEq(token2.balanceOf(beneficiary1), 1000 * 1e18);
    }
}
