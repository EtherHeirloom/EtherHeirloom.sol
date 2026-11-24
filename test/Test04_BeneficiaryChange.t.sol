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
 * @title Test 4: Beneficiary Change Edge Case
 * @notice Tests that changing beneficiary configuration works correctly
 * @dev Scenario: Owner changes beneficiaries (2x50% -> 3x40/30/30%) and totalAllocatedShares updates correctly
 */
contract Test04_BeneficiaryChange is Test {
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

        // Transfer tokens to owner
        token.transfer(owner, 1000 * 1e18);

        // Owner approves unlimited
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

    function test_ChangeBeneficiaryConfiguration() public {
        // Initial setup: 2 beneficiaries at 50% each
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Verify initial setup
        assertEq(heirloom.totalAllocatedShares(owner), 10000);

        // Change to 3 beneficiaries: 40%, 30%, 30%
        address[] memory newBeneficiaries = new address[](3);
        newBeneficiaries[0] = beneficiary1;
        newBeneficiaries[1] = beneficiary2;
        newBeneficiaries[2] = beneficiary3;

        uint16[] memory newShares = new uint16[](3);
        newShares[0] = 4000; // 40%
        newShares[1] = 3000; // 30%
        newShares[2] = 3000; // 30%

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(newBeneficiaries, newShares, 100);

        // Verify new configuration
        assertEq(heirloom.totalAllocatedShares(owner), 10000);

        // Verify individual shares
        uint16 share1 = _getLegacy(owner, beneficiary1).share;
        uint16 share2 = _getLegacy(owner, beneficiary2).share;
        uint16 share3 = _getLegacy(owner, beneficiary3).share;

        assertEq(share1, 4000);
        assertEq(share2, 3000);
        assertEq(share3, 3000);
    }

    function test_RemoveBeneficiary() public {
        // Initial setup: 3 beneficiaries
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 4000; // 40%
        shares[1] = 3000; // 30%
        shares[2] = 3000; // 30%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Remove beneficiary3, redistribute to B1=60%, B2=40%
        address[] memory newBeneficiaries = new address[](2);
        newBeneficiaries[0] = beneficiary1;
        newBeneficiaries[1] = beneficiary2;

        uint16[] memory newShares = new uint16[](2);
        newShares[0] = 6000; // 60%
        newShares[1] = 4000; // 40%

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(newBeneficiaries, newShares, 100);

        // Verify B3 is no longer active
        bool isActive = _getLegacy(owner, beneficiary3).isActive;
        assertEq(isActive, false);

        // Verify new shares
        uint16 share1 = _getLegacy(owner, beneficiary1).share;
        uint16 share2 = _getLegacy(owner, beneficiary2).share;

        assertEq(share1, 6000);
        assertEq(share2, 4000);
        assertEq(heirloom.totalAllocatedShares(owner), 10000);
    }

    function test_AddNewBeneficiary() public {
        // Initial setup: 1 beneficiary at 100%
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims everything
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 1000 * 1e18);

        // Owner adds B2 as 50/50 split
        address[] memory newBeneficiaries = new address[](2);
        newBeneficiaries[0] = beneficiary1;
        newBeneficiaries[1] = beneficiary2;

        uint16[] memory newShares = new uint16[](2);
        newShares[0] = 5000; // 50%
        newShares[1] = 5000; // 50%

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(newBeneficiaries, newShares, 100);

        skip(101);

        // Owner receives 1000 more tokens
        token.transfer(owner, 1000 * 1e18);

        // B1 virtual pool: 1000 + 1000 = 2000, due: 1000, claimed: 1000, new: 0
        // Should revert when no assets due
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // B2 virtual pool: 1000 + 1000 = 2000, due: 1000, claimed: 0, new: 1000
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 1000 * 1e18);
    }

    function test_CompletelyReplaceAllBeneficiaries() public {
        // Initial setup: B1=50%, B2=50%
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Replace with completely different beneficiary: B3=100%
        address[] memory newBeneficiaries = new address[](1);
        newBeneficiaries[0] = beneficiary3;

        uint16[] memory newShares = new uint16[](1);
        newShares[0] = 10000; // 100%

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(newBeneficiaries, newShares, 100);

        // Verify old beneficiaries are inactive
        EtherHeirloom.LegacyAccount memory l1 = _getLegacy(owner, beneficiary1);
        EtherHeirloom.LegacyAccount memory l2 = _getLegacy(owner, beneficiary2);
        assertEq(l1.isActive, false);
        assertEq(l2.isActive, false);

        // Verify new beneficiary is active
        EtherHeirloom.LegacyAccount memory l3 = _getLegacy(owner, beneficiary3);
        assertEq(l3.isActive, true);

        skip(101);

        // B1 and B2 cannot claim (legacy not active)
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.LegacyNotActive.selector);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        vm.expectRevert(EtherHeirloom.LegacyNotActive.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);

        // B3 can claim everything
        vm.deal(beneficiary3, 10 ether);
        vm.prank(beneficiary3);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary3, tokens);
        assertEq(token.balanceOf(beneficiary3), 1000 * 1e18);
    }

    function test_ChangeAfterPartialClaims() public {
        // Initial setup: B1=70%, B2=30%
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 7000; // 70%
        shares[1] = 3000; // 30%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims 700 tokens
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
        assertEq(token.balanceOf(beneficiary1), 700 * 1e18);

        // Owner changes to B1=20%, B2=80%
        uint16[] memory newShares = new uint16[](2);
        newShares[0] = 2000; // 20%
        newShares[1] = 8000; // 80%

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, newShares, 100);

        skip(101);

        // B2 claims: virtual pool = 300 + 700 = 1000, due = 800, claimed = 0, new = 800
        // But only 300 available
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 300 * 1e18);

        // Owner now has 0 tokens
        assertEq(token.balanceOf(owner), 0);

        // B1 tries to claim: virtual pool = 0 + 700 = 700, due = 140, claimed = 700
        // Due is less than claimed - should revert
        vm.prank(beneficiary1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);
    }

    function test_TotalClaimedPreservedAcrossChanges() public {
        // Setup B1 at 100%
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // B1 claims 1000 tokens
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens);

        // Verify legacy is still active
        EtherHeirloom.LegacyAccount memory l1 = _getLegacy(owner, beneficiary1);
        assertEq(l1.isActive, true);

        // Change configuration to B1=50%, B2=50%
        address[] memory newBeneficiaries = new address[](2);
        newBeneficiaries[0] = beneficiary1;
        newBeneficiaries[1] = beneficiary2;

        uint16[] memory newShares = new uint16[](2);
        newShares[0] = 5000;
        newShares[1] = 5000;

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(newBeneficiaries, newShares, 100);

        // Verify B1's configuration updated correctly
        // beneficiaryClaims tracks per-token claims for virtual pool calculation
        EtherHeirloom.LegacyAccount memory l1_after = _getLegacy(owner, beneficiary1);
        assertEq(l1_after.share, 5000);
        assertEq(l1_after.isActive, true);
    }

    function test_NoDuplicateBeneficiariesInList() public {
        // Try to setup with duplicate beneficiaries
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary1; // Duplicate!

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000;
        shares[1] = 5000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherHeirloom.DuplicateBeneficiary.selector, beneficiary1));
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }
}
