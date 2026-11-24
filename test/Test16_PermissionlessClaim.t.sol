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
 * @title Test 16: Permissionless Claiming
 * @notice Tests that any address can trigger claims if they pay the fee
 */
contract Test16_PermissionlessClaim is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(0x101);
    address public beneficiary = address(0x102);
    address public thirdParty = address(0x103);
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

    function test_ThirdPartyClaim() public {
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

        // Third party triggers claim
        vm.deal(thirdParty, 1 ether);
        uint256 thirdPartyStartBalance = thirdParty.balance;
        uint256 beneficiaryStartTokenBalance = token.balanceOf(beneficiary);

        vm.prank(thirdParty);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Verify tokens went to BENEFICIARY, not third party
        assertEq(token.balanceOf(beneficiary), beneficiaryStartTokenBalance + 1000 * 1e18, "Beneficiary should receive tokens");
        assertEq(token.balanceOf(thirdParty), 0, "Third party should receive NO tokens");

        // Verify fees paid by THIRD PARTY
        uint256 feePaid = thirdPartyStartBalance - thirdParty.balance;
        assertEq(feePaid, 0.0005 ether, "Third party should pay the operation fee");
    }

    function test_ThirdPartyCannotRedirectFunds() public {
        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Third party tries to claim for THEMSELVES by passing wrong beneficiary address?
        // No, contract checks _legacies[_owner][_beneficiary].beneficiary matches.
        // If third party passes themselves as beneficiary argument, legacy lookup will fail/return empty.
        
        vm.deal(thirdParty, 1 ether);
        
        vm.prank(thirdParty);
        vm.expectRevert(abi.encodeWithSelector(EtherHeirloom.NotBeneficiary.selector, owner, thirdParty));
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, thirdParty, tokens);
    }

    function test_BatchClaimPermissionless() public {
        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.deal(thirdParty, 1 ether);
        uint256 thirdPartyStartBalance = thirdParty.balance;

        vm.prank(thirdParty);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Verify tokens went to BENEFICIARY
        assertEq(token.balanceOf(beneficiary), 1000 * 1e18, "Beneficiary should receive tokens");
        
        // Verify fees paid by THIRD PARTY
        uint256 feePaid = thirdPartyStartBalance - thirdParty.balance;
        assertEq(feePaid, 0.0005 ether, "Third party should pay the operation fee");
    }
}
