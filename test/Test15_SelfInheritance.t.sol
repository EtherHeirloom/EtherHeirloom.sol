// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/EtherHeirloom.sol";

contract Test15_SelfInheritance is Test {
    EtherHeirloom public heirloom;
    address public feeRecipient = address(0x999);
    address public owner = address(0x1);
    address public beneficiary1 = address(0x2);

    function setUp() public {
        heirloom = new EtherHeirloom(
            feeRecipient,
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );
        vm.deal(owner, 10 ether);
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

    function test_CannotSetSelfAsBeneficiary() public {
        vm.startPrank(owner);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = owner; // ❌ Owner trying to set themselves

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        uint256 setupFee = heirloom.setupFee();

        vm.expectRevert(EtherHeirloom.OwnerCannotBeBeneficiary.selector);
        heirloom.setupLegacies{value: setupFee}(
            beneficiaries,
            shares,
            365 days
        );

        vm.stopPrank();
    }

    function test_CannotSetSelfAmongMultipleBeneficiaries() public {
        vm.startPrank(owner);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1; // ✅ Valid
        beneficiaries[1] = owner;         // ❌ Owner trying to sneak in

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        uint256 setupFee = heirloom.setupFee();

        vm.expectRevert(EtherHeirloom.OwnerCannotBeBeneficiary.selector);
        heirloom.setupLegacies{value: setupFee}(
            beneficiaries,
            shares,
            365 days
        );

        vm.stopPrank();
    }

    function test_ValidSetupWithoutSelf() public {
        vm.startPrank(owner);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1; // ✅ Not owner

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        uint256 setupFee = heirloom.setupFee();

        // Should succeed
        heirloom.setupLegacies{value: setupFee}(
            beneficiaries,
            shares,
            365 days
        );

        vm.stopPrank();

        // Verify setup
        EtherHeirloom.LegacyAccount memory legacy = _getLegacy(owner, beneficiary1);
        assertEq(legacy.share, 10000, "Share should be 100%");
        assertTrue(legacy.isActive, "Legacy should be active");
    }

    function test_CannotUseZeroAddressAsBeneficiary() public {
        vm.startPrank(owner);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = address(0); // ❌ Zero address

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        uint256 setupFee = heirloom.setupFee();

        vm.expectRevert(EtherHeirloom.InvalidBeneficiaryAddress.selector);
        heirloom.setupLegacies{value: setupFee}(
            beneficiaries,
            shares,
            365 days
        );

        vm.stopPrank();
    }

    function test_MultipleValidBeneficiariesWithoutOwner() public {
        vm.startPrank(owner);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = address(0x10);
        beneficiaries[1] = address(0x20);
        beneficiaries[2] = address(0x30);

        uint16[] memory shares = new uint16[](3);
        shares[0] = 3333;  // 33.33%
        shares[1] = 3333;  // 33.33%
        shares[2] = 3334;  // 33.34%

        uint256 setupFee = heirloom.setupFee();

        // Should succeed
        heirloom.setupLegacies{value: setupFee}(
            beneficiaries,
            shares,
            365 days
        );

        vm.stopPrank();

        // Verify all beneficiaries
        for (uint i = 0; i < 3; i++) {
            EtherHeirloom.LegacyAccount memory legacy = _getLegacy(owner, beneficiaries[i]);
            assertEq(legacy.share, shares[i], "Share mismatch");
            assertTrue(legacy.isActive, "Legacy should be active");
        }
    }
}
