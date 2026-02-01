// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/EtherHeirloom.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockTokenWithFee
 * @notice ERC20 token that charges 1% fee on every transfer
 * @dev Simulates tokens like PAXG, STA, etc. that have transfer fees
 */
contract MockTokenWithFee is ERC20 {
    uint256 public constant FEE_PERCENTAGE = 1; // 1% fee
    address public feeCollector;

    constructor() ERC20("FeeToken", "FEE") {
        _mint(msg.sender, 1000000 * 1e18);
        feeCollector = msg.sender;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);

        // Calculate fee (1% of amount)
        uint256 fee = (amount * FEE_PERCENTAGE) / 100;
        uint256 amountAfterFee = amount - fee;

        // Transfer fee to collector
        _transfer(from, feeCollector, fee);

        // Transfer remaining amount to recipient
        _transfer(from, to, amountAfterFee);

        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = _msgSender();

        // Calculate fee
        uint256 fee = (amount * FEE_PERCENTAGE) / 100;
        uint256 amountAfterFee = amount - fee;

        // Transfer fee to collector
        _transfer(owner, feeCollector, fee);

        // Transfer remaining amount to recipient
        _transfer(owner, to, amountAfterFee);

        return true;
    }
}

/**
 * @title Test 12: Fee-on-Transfer Tokens Edge Case
 * @notice Verifies that EtherHeirloom correctly measures "actual received amount"
 * to maintain precise virtual pool accounting even with transfer fees.
 */
contract Test12_FeeOnTransfer is Test {
    EtherHeirloom public heirloom;
    MockTokenWithFee public feeToken;

    address public owner = address(0x101);
    address public beneficiary = address(0x102);
    address public beneficiary2 = address(0x103);
    address public feeRecipient = address(0x104);

    function setUp() public {
        heirloom = new EtherHeirloom(
            feeRecipient,
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );
        feeToken = new MockTokenWithFee();

        // Transfer tokens to owner
        // NOTE: Initial transfer also incurs fee!
        // 1000 sends, 990 arrives to owner.
        feeToken.transfer(owner, 1000 * 1e18);

        // Owner approves unlimited
        vm.prank(owner);
        feeToken.approve(address(heirloom), type(uint256).max);
    }

    /**
     * @notice Verifies basic claim accounts for fee correctly
     */
    function test_FeeOnTransfer_BasicClaim() public {
        // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        uint256 ownerBalance = feeToken.balanceOf(owner); // 990

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        uint256 beneficiaryReceived = feeToken.balanceOf(beneficiary);

        // Expected: Owner transfers 990. 1% fee taken on transfer.
        // Beneficiary receives: 990 * 0.99 = 980.1
        uint256 expected = (ownerBalance * 99) / 100;

        assertEq(beneficiaryReceived, expected, "Beneficiary should receive exact amount minus fee");

        // Verify Protocol Accounting
        uint256 released = heirloom.ownerTokenReleased(owner, address(feeToken));

        // CRITICAL: Released must match ACTUAL received amount, NOT requested amount.
        assertEq(released, beneficiaryReceived, "Virtual Pool accounting must match received amount");
    }

    /**
     * @notice Verifies 50/50 split works without error accumulation
     */
    function test_FeeOnTransfer_PartialShares() public {
        // Setup: 50/50 split
        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary;
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        uint256 ownerInitial = feeToken.balanceOf(owner); // 990
        
        // --- Claim B1 ---
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        uint256 b1Received = feeToken.balanceOf(beneficiary);
        // Payment due: 990 * 50% = 495.
        // Transfer 495. Fee 1%. Received: 495 * 0.99 = 490.05
        uint256 expectedB1 = (ownerInitial * 50 * 99) / (100 * 100);
        assertEq(b1Received, expectedB1, "B1 amount wrong");

        // --- Claim B2 ---
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);

        uint256 b2Received = feeToken.balanceOf(beneficiary2);
        
        // Calculation for B2:
        // Current Owner Balance: 495.
        // Released (B1): 490.05.
        // Virtual Pool: 495 + 490.05 = 985.05.
        // B2 Share 50%: 492.525.
        // Transfer: 492.525.
        // Fee (1%): 4.92525.
        // B2 Net: 487.59975.
        uint256 expectedB2 = 487599750000000000000; 
        
        // Allow small rounding error (100 wei)
        assertApproxEqAbs(b2Received, expectedB2, 100, "B2 amount wrong");

        // Total Released in Protocol
        uint256 totalReleased = heirloom.ownerTokenReleased(owner, address(feeToken));
        uint256 totalReceived = b1Received + b2Received;

        assertEq(totalReleased, totalReceived, "Total released must equal total received");
        
        // Owner remaining balance:
        // Initial 990.
        // Paid B1: 495.
        // Paid B2: 492.525.
        // Remaining: 2.475.
        uint256 expectedRemaining = 2475000000000000000;
        uint256 ownerRemaining = feeToken.balanceOf(owner);
        
        assertEq(ownerRemaining, expectedRemaining, "Owner should have dust remaining due to FoT math");
    }

    /**
     * @notice Verifies refill works correctly
     */
    function test_FeeOnTransfer_Refill() public {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // First Claim
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        uint256 firstClaim = feeToken.balanceOf(beneficiary);

        // Refill: Owner gets 100 more tokens
        // Fee deducted on transfer TO owner: 100 * 0.99 = 99 arrives
        feeToken.transfer(owner, 100 * 1e18);
        uint256 ownerRefilledBalance = feeToken.balanceOf(owner);
        assertEq(ownerRefilledBalance, 99 * 1e18, "Owner should have 99 tokens");

        // Second Claim
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        uint256 totalBalance = feeToken.balanceOf(beneficiary);
        uint256 secondClaim = totalBalance - firstClaim;
        
        // Beneficiary should get entire refill amount minus fee
        // 99 transfers -> 99 * 0.99 = 98.01
        uint256 expectedSecond = (ownerRefilledBalance * 99) / 100;
        
        assertEq(secondClaim, expectedSecond, "Refill claim amount incorrect");
        assertEq(feeToken.balanceOf(owner), 0, "Owner should be empty again");
    }

    /**
     * @notice Verifies batch claiming works with fee tokens
     */
    function test_FeeOnTransfer_BatchClaim() public {
         // Setup legacy with 100% allocation
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);
        
        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.001 ether}(owner, beneficiary, tokens);
        
        uint256 beneficiaryReceived = feeToken.balanceOf(beneficiary);
        assertGt(beneficiaryReceived, 0, "Should receive tokens");
        assertEq(feeToken.balanceOf(owner), 0, "Owner should be drained");
    }
}
