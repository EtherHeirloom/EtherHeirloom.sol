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
 * @title Malicious Reentrancy Attacker
 * @notice Tries to re-enter setupLegacies during the fee payment callback
 */
contract ReentrancyAttacker {
    EtherHeirloom public target;
    address[] public beneficiaries;
    uint16[] public shares;
    bool public attacked;

    constructor(address _target) {
        target = EtherHeirloom(_target);
        beneficiaries.push(address(0x1));
        shares.push(10000);
    }

    // Try to start the attack
    function attack() external payable {
        target.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    // Callback - try to re-enter
    receive() external payable {
        if (!attacked) {
            attacked = true;
            // Attempt reentrancy
            target.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
        }
    }
}

/**
 * @title Test 13: Negative Shares / Overflow / Reentrancy Edge Cases
 * @notice Verifies input validation and security modifiers
 */
contract Test13_NegativeSharesOverflow is Test {
    EtherHeirloom public heirloom;
    MockToken public token;

    address public owner = address(0x101);
    address public beneficiary1 = address(0x102);
    address public beneficiary2 = address(0x103);
    address public beneficiary3 = address(0x105);
    address public feeRecipient = address(0x104);

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

    /**
     * @notice Test rejection of shares that would overflow to 100%
     */
    function test_RejectOverflowingShares() public {
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 5000;  // 50%
        shares[1] = 10000; // 100%
        shares[2] = type(uint16).max - 4999; // ~60536
        // Sum: > 65535. Overflow check is implicit in logic.

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        // Should revert check (60536 > 10000)
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test rejection of max uint16 value
     */
    function test_RejectMaxUint16Value() public {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;

        uint16[] memory shares = new uint16[](1);
        shares[0] = type(uint16).max; // 65535

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test attempting to create "underflow" share (conceptually)
     */
    function test_CannotCreateNegativeShare() public {
        // Closest to "negative" in uint16 is a large number near max
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 5000;
        shares[1] = 10000;
        shares[2] = 60536; // Large number

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        // Caught at individual validation
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test that large shares are caught by individual validation
     */
    function test_LargeSharesCaughtIndividually() public {
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000;  // Valid (50%)
        shares[1] = 15000; // Invalid (150%) - > 10000

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test passing 10001 (100.01%) - just over limit
     */
    function test_RejectJustOverMaxShare() public {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary1;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10001; // 100.01%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.InvalidShare.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test multiple large shares that each pass individual check but fail total
     */
    function test_RejectValidIndividualSharesInvalidTotal() public {
        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        beneficiaries[2] = beneficiary3;

        uint16[] memory shares = new uint16[](3);
        shares[0] = 9999; // Each individually valid (< 10000)
        shares[1] = 9999;
        shares[2] = 9999;
        // Total: 29997 (>> 10000)

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TotalSharesMismatch.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test attempting integer overflow protections
     */
    function test_OverflowInTotalCalculation() public {
        // Try precise overflow: 2 shares of 32768? 
        // 32768 + 32768 = 65536 (overflows uint16 to 0)
        // BUT our contract calculates total in uint256 tracking (mapping(address => uint256))
        // So it won't overflow the tracker.
        
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;
        
        uint16[] memory shares = new uint16[](2);
        shares[0] = 10000;
        shares[1] = 10000; 
        // Total 20000 in uint256 accumulator.
        // Should revert TotalSharesMismatch (20000 != 10000)

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        vm.expectRevert(EtherHeirloom.TotalSharesMismatch.selector);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test actual REENTRANCY protection
     */
    function test_CannotBypassWithReentrancy() public {
        // Deploy malicious fee recipient
        // The contract pays FEE to FeeRecipient at the END of setupLegacies
        // So we need to exploit the fee transfer.
        // If we make the FeeRecipient the attacker, it will be called at the end.
        
        // 1. Setup new Heirloom with Attacker as fee recipient
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(0)); // Deploy first to get address
        EtherHeirloom victim = new EtherHeirloom(
            address(attacker),
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );
        
        // Re-init attacker with correct target
        attacker = new ReentrancyAttacker(address(victim));
        
        // We need to update the victim to use THIS new attacker as fee recipient?
        // Actually, easiest is just to pass attacker address to constructor.
        victim = new EtherHeirloom(
            address(attacker),
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );
        
        vm.deal(address(attacker), 10 ether);
        
        // Attacker calls setupLegacies
        // Inside setupLegacies:
        // 1. Logic runs
        // 2. Fees transferred to attacker (attacker.receive() triggers)
        // 3. attacker.receive() calls setupLegacies AGAIN
        // 4. The inner call reverts with ReentrancyGuardReentrantCall
        // 5. The generic .call returns false
        // 6. The main contract reverts with FeeTransferFailed
        
        vm.expectRevert(EtherHeirloom.FeeTransferFailed.selector);
        attacker.attack();
    }
}
