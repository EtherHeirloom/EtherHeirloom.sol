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
 * @title Test 11: Negative/Invalid Shares Edge Case
 * @notice Tests that contract rejects invalid share configurations
 * @dev Scenario: Tests with shares that sum to 100% but contain invalid values
 */
contract Test11_NegativeShares is Test {
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

    function test_RejectZeroShare() public {
        // Try to setup with 0% share
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 0; // 0% - invalid
        shares[1] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_RejectShareOver100Percent() public {
        // Try to setup with share > 100%
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10001; // 100.01% - invalid

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_RejectTotalSharesOver100Percent() public {
        // Try to setup with total shares > 100%
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 6000; // 60%
        shares[1] = 5000; // 50%
        // Total: 110%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TotalSharesMismatch.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_RejectTotalSharesUnder100Percent() public {
        // Try to setup with total shares < 100%
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 4000; // 40%
        shares[1] = 5000; // 50%
        // Total: 90%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TotalSharesMismatch.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_RejectMaxUint16Share() public {
        // Try to setup with max uint16 value
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = type(uint16).max; // 65535 = 655.35%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_AcceptExact100Percent() public {
        // Valid: exactly 100%
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // Exactly 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Verify it was set correctly
        assertEq(heirloom.totalAllocatedShares(owner), 10000);
    }

    function test_AcceptMinimumShare() public {
        // Valid: minimum share is 1 basis point (0.01%)
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 1; // 0.01%
        shares[1] = 9999; // 99.99%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        assertEq(heirloom.totalAllocatedShares(owner), 10000);
    }

    function test_AcceptMaximumIndividualShare() public {
        // Valid: one beneficiary gets exactly 100%
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        assertEq(heirloom.totalAllocatedShares(owner), 10000);
    }

    function test_RejectMismatchedArrayLengths() public {
        // Try to setup with mismatched array lengths
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](1); // Wrong length!
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.MismatchedInputs.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_ComplexValidDistribution() public {
        // Complex but valid distribution
        address[] memory beneficiaries = new address[](5);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;
        beneficiaries[3] = address(6);
        beneficiaries[4] = address(7);

        uint16[] memory shares = new uint16[](5);
        shares[0] = 2500; // 25%
        shares[1] = 2500; // 25%
        shares[2] = 2000; // 20%
        shares[3] = 1500; // 15%
        shares[4] = 1500; // 15%
        // Total: 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        assertEq(heirloom.totalAllocatedShares(owner), 10000);
    }

    function test_RejectComplexInvalidDistribution() public {
        // Complex invalid distribution (total = 99.99%)
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 3333; // 33.33%
        shares[1] = 3333; // 33.33%
        shares[2] = 3333; // 33.33%
        // Total: 9999 = 99.99%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TotalSharesMismatch.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_SingleBasisPointDistribution() public {
        // Valid: 10000 beneficiaries with 1 basis point each (theoretical)
        // Practical test with 10 beneficiaries at 10% each
        address[] memory beneficiaries = new address[](10);
        uint16[] memory shares = new uint16[](10);

        for (uint i = 0; i < 10; i++) {
            beneficiaries[i] = address(uint160(100 + i));
            shares[i] = 1000; // 10% each
        }

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        assertEq(heirloom.totalAllocatedShares(owner), 10000);
    }

    function test_RejectTooManyBeneficiaries() public {
        // Try to setup with more than MAX_BENEFICIARIES (10)
        address[] memory beneficiaries = new address[](11);
        uint16[] memory shares = new uint16[](11);

        for (uint i = 0; i < 11; i++) {
            beneficiaries[i] = address(uint160(100 + i));
            shares[i] = 909; // Won't sum to 10000, but should fail before that check
        }

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TooManyBeneficiaries.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_SharesPersistCorrectly() public {
        // Setup shares and verify they persist correctly
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 5000; // 50%
        shares[1] = 3000; // 30%
        shares[2] = 2000; // 20%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Verify each share
        uint16 share1 = _getLegacy(owner, beneficiary1).share;
        uint16 share2 = _getLegacy(owner, beneficiary2).share;
        uint16 share3 = _getLegacy(owner, beneficiary3).share;

        assertEq(share1, 5000);
        assertEq(share2, 3000);
        assertEq(share3, 2000);
    }

    function test_OverflowProtection() public {
        // Test that total shares calculation doesn't overflow
        // With uint16 max = 65535, this shouldn't be possible, but let's verify the check
        address[] memory beneficiaries = new address[](10);
        uint16[] memory shares = new uint16[](10);

        for (uint i = 0; i < 10; i++) {
            beneficiaries[i] = address(uint160(100 + i));
            shares[i] = 6553; // Would overflow if summed as uint16: 65530
        }

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TotalSharesMismatch.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function test_UnderflowProtection() public {
        // Test with very small shares summing to less than 100%
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 1; // 0.01%
        shares[1] = 1; // 0.01%
        shares[2] = 1; // 0.01%
        // Total: 0.03%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TotalSharesMismatch.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }
}
