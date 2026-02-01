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

contract EtherHeirloomTest is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(1);
    address public beneficiary1 = address(2);
    address public beneficiary2 = address(3);
    address public feeRecipient = address(4);

    function setUp() public {
        heirloom = new EtherHeirloom(
            feeRecipient,
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );
        token = new MockToken();
        token.transfer(owner, 1000 * 1e18);

        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    function test_VirtualPoolRecalculation() public {
        // 1. Setup: 50/50 shares
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Advance time
        skip(101);

        // 2. Beneficiary 1 claims his 50% of 1000 tokens (500)
        vm.deal(beneficiary1, 10 ether);
        vm.prank(beneficiary1);
        address[] memory tokens1 = new address[](1);
        tokens1[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens1);
        assertEq(token.balanceOf(beneficiary1), 500 * 1e18);

        // 3. Owner changes configuration: 10% to B1, 90% to B2
        shares[0] = 1000; // 10%
        shares[1] = 9000; // 90%
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Advance time again
        skip(101);

        // 4. Beneficiary 2 claims.
        // Virtual pool is 500 (current) + 500 (released) = 1000.
        // B2's new share is 90% of 1000 = 900.
        // But only 500 tokens are available, so B2 gets 500.
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        address[] memory tokens2 = new address[](1);
        tokens2[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens2);
        assertEq(token.balanceOf(beneficiary2), 500 * 1e18);

        // 5. Owner receives 400 more tokens (refill scenario)
        token.transfer(owner, 400 * 1e18);

        // 6. Beneficiary 2 claims again, should get remaining 400 tokens (900 total - 500 already claimed)
        vm.prank(beneficiary2);
        address[] memory tokens3 = new address[](1);
        tokens3[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens3);
        assertEq(token.balanceOf(beneficiary2), 900 * 1e18);

        // 7. Check Beneficiary 1 again.
        // His 10% of 1000 is 100. He already took 500.
        // Should revert when no assets due
        vm.prank(beneficiary1);
        address[] memory tokens4 = new address[](1);
        tokens4[0] = address(token);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary1, tokens4);
    }
}
