// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/EtherHeirloom.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RegressionToken is ERC20 {
    constructor() ERC20("Regression", "RGR") {
        _mint(msg.sender, 1_000_000e18);
    }
}

/**
 * @title Test 17: regressions found in review of PR #10 and issue #2
 * @notice PR #10 dropped index-based removal and left beneficiaryOwners stale (duplicates and removed heirs
 *         kept seeing the plan). Issue #2: with 50/50 shares a double claim must not reduce the other heir's share.
 */
contract Test17_ReviewRegressions is Test {
    EtherHeirloom public heirloom;
    RegressionToken public token;

    address public owner = address(0x101);
    address public b1 = address(0x102);
    address public b2 = address(0x103);

    function setUp() public {
        heirloom = new EtherHeirloom(address(0x104), 0.001 ether, 0.0005 ether, 0.0001 ether);
        token = new RegressionToken();
        token.transfer(owner, 1000e18);
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
        vm.deal(owner, 10 ether);
        vm.deal(b1, 1 ether);
        vm.deal(b2, 1 ether);
    }

    function _setup(address[] memory beneficiaries, uint16[] memory shares) internal {
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    function _single(address a) internal pure returns (address[] memory r, uint16[] memory s) {
        r = new address[](1);
        r[0] = a;
        s = new uint16[](1);
        s[0] = 10_000;
    }

    function _claim(address beneficiary) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }

    function test_ResetupSameHeir_noDuplicatesForBeneficiary() public {
        (address[] memory r, uint16[] memory s) = _single(b1);
        _setup(r, s);
        _setup(r, s);
        assertEq(heirloom.getHeirloomsForBeneficiary(b1, 0, 50).length, 1);
    }

    function test_ReplaceHeir_removedHeirNoLongerListed() public {
        (address[] memory r1, uint16[] memory s) = _single(b1);
        (address[] memory r2,) = _single(b2);
        _setup(r1, s);
        _setup(r2, s);
        assertEq(heirloom.getHeirloomsForBeneficiary(b1, 0, 50).length, 0);
        assertEq(heirloom.getHeirloomsForBeneficiary(b2, 0, 50).length, 1);
    }

    function test_Issue2_DoubleClaimDoesNotHurtOtherHeir() public {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000;
        shares[1] = 5000;
        _setup(beneficiaries, shares);
        skip(101);

        _claim(b1);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        _claim(b1);
        _claim(b2);

        assertEq(token.balanceOf(b1), 500e18);
        assertEq(token.balanceOf(b2), 500e18);
        assertEq(token.balanceOf(owner), 0);
    }
}
