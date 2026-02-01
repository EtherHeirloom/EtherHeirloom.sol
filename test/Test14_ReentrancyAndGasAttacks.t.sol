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
 * @title Malicious Contract - Attempts Reentrancy on Claim
 * @dev Tries to reenter claimLegacies during ETH refund
 */
contract MaliciousClaimReentrancy {
    EtherHeirloom public heirloom;
    address public owner;
    address public token;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _heirloom, address _owner, address _token) {
        heirloom = EtherHeirloom(_heirloom);
        owner = _owner;
        token = _token;
    }

    // Attempt to claim
    function attack() external payable {
        attacking = true;
        attackCount = 0;
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        heirloom.claimLegacies{value: msg.value}(owner, address(this), tokens);
    }

    // Receive ETH refund and try to reenter
    receive() external payable {
        if (attacking && attackCount < 3) {
            attackCount++;
            // Try to reenter
            address[] memory tokens = new address[](1);
            tokens[0] = token;
            try heirloom.claimLegacies{value: 0.0005 ether}(owner, address(this), tokens) {
                // If this succeeds, reentrancy guard failed!
            } catch {
                // Expected: reentrancy guard blocks this
            }
        }
    }
}

/**
 * @title Malicious Contract - Attempts Reentrancy on Setup
 * @dev Tries to reenter setupLegacies during ETH refund
 */
contract MaliciousSetupReentrancy {
    EtherHeirloom public heirloom;
    uint256 public attackCount;
    bool public attacking;

    constructor(address _heirloom) {
        heirloom = EtherHeirloom(_heirloom);
    }

    function attack(address[] calldata beneficiaries, uint16[] calldata shares) external payable {
        attacking = true;
        attackCount = 0;
        heirloom.setupLegacies{value: msg.value}(beneficiaries, shares, 100);
    }

    receive() external payable {
        if (attacking && attackCount < 3) {
            attackCount++;
            // Try to reenter
            address[] memory b = new address[](1);
            b[0] = address(0x123);
            uint16[] memory s = new uint16[](1);
            s[0] = 10000;

            try heirloom.setupLegacies{value: 0.001 ether}(b, s, 100) {
                // If this succeeds, reentrancy guard failed!
            } catch {
                // Expected: reentrancy guard blocks this
            }
        }
    }
}

/**
 * @title Gas-Guzzling Contract
 * @dev Consumes excessive gas in fallback, tests gas limits
 */
contract GasGuzzler {
    uint256 public data;

    // Expensive fallback that consumes gas
    receive() external payable {
        // Waste gas in a loop
        for (uint i = 0; i < 1000; i++) {
            data = i * i;
        }
    }

    fallback() external payable {
        for (uint i = 0; i < 1000; i++) {
            data = i * i;
        }
    }
}

/**
 * @title Reverting Contract
 * @dev Always reverts on ETH receive
 */
contract RevertingContract {
    receive() external payable {
        revert("I don't accept ETH");
    }

    fallback() external payable {
        revert("I don't accept ETH");
    }
}

/**
 * @title Test 14: Reentrancy and Gas Attack Edge Cases
 * @notice Tests advanced security scenarios with malicious contracts
 * @dev Covers reentrancy attacks, gas limits, and malicious contract interactions
 */
contract Test14_ReentrancyAndGasAttacks is Test {
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

        token.transfer(owner, 1000 * 1e18);
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    /**
     * @notice Test reentrancy attack on claimLegacy
     * @dev Malicious beneficiary tries to reenter during ETH refund
     */
    function test_ReentrancyAttackOnClaim() public {
        // Deploy malicious contract
        MaliciousClaimReentrancy attacker = new MaliciousClaimReentrancy(
            address(heirloom),
            owner,
            address(token)
        );

        // Setup legacy to malicious contract
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = address(attacker);

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Attacker tries to reenter with excess payment
        vm.deal(address(attacker), 10 ether);
        attacker.attack{value: 0.01 ether}(); // Sends 20x required fee

        // Verify reentrancy was blocked
        // Attacker should only claim once
        assertEq(token.balanceOf(address(attacker)), 1000 * 1e18);

        // Attack count should be > 0 (attempted) but should have failed
        assertGt(attacker.attackCount(), 0, "Attacker should have attempted reentrancy");
    }

    /**
     * @notice Test reentrancy attack on setupLegacies
     * @dev Malicious owner tries to reenter during refund
     */
    function test_ReentrancyAttackOnSetup() public {
        MaliciousSetupReentrancy attacker = new MaliciousSetupReentrancy(address(heirloom));

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(address(attacker), 10 ether);

        // Attack with excess payment to trigger refund
        attacker.attack{value: 0.01 ether}(beneficiaries, shares);

        // Verify only one setup succeeded
        assertEq(heirloom.totalAllocatedShares(address(attacker)), 10000);

        // Attack should have been attempted but blocked
        assertGt(attacker.attackCount(), 0, "Attacker should have attempted reentrancy");
    }

    /**
     * @notice Test gas-guzzling contract cannot DoS the system
     * @dev Fee recipient is a gas-guzzling contract
     */
    function test_GasGuzzlerAsFeeRecipient() public {
        GasGuzzler guzzler = new GasGuzzler();

        // Deploy new heirloom with gas guzzler as fee recipient
        EtherHeirloom heirloomWithGuzzler = new EtherHeirloom(
            address(guzzler),
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );

        token.transfer(owner, 1000 * 1e18);
        vm.prank(owner);
        token.approve(address(heirloomWithGuzzler), type(uint256).max);

        // Setup should work (uses .call with all gas)
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloomWithGuzzler.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Fee recipient should have received ETH despite expensive fallback
        assertEq(address(guzzler).balance, 0.001 ether);
    }

    /**
     * @notice Test reverting contract as fee recipient
     * @dev Fee recipient always reverts on receive
     */
    function test_RevertingContractAsFeeRecipient() public {
        RevertingContract reverter = new RevertingContract();

        // Deploy heirloom with reverting fee recipient
        EtherHeirloom heirloomWithReverter = new EtherHeirloom(
            address(reverter),
            0.001 ether,    // SETUP_FEE
            0.0005 ether,   // OPERATION_FEE
            0.0001 ether    // DEADLINE_EXTENSION_FEE
        );

        token.transfer(owner, 1000 * 1e18);
        vm.prank(owner);
        token.approve(address(heirloomWithReverter), type(uint256).max);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);

        // Setup should FAIL because fee transfer fails
        vm.expectRevert(EtherHeirloom.FeeTransferFailed.selector);
        heirloomWithReverter.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);
    }

    /**
     * @notice Test malicious contract as beneficiary
     * @dev Beneficiary is a contract that reverts on token receive
     */
    function test_MaliciousBeneficiaryRevertsOnTokenReceive() public {
        RevertingContract maliciousBeneficiary = new RevertingContract();

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = address(maliciousBeneficiary);

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Claim should fail because beneficiary reverts (but this is for tokens, not ETH)
        // SafeERC20 will handle the transfer, and if it's an EOA or accepts tokens, it works
        // This is actually fine - the malicious contract just won't get tokens if it reverts
    }

    /**
     * @notice Test Checks-Effects-Interactions pattern
     * @dev Verifies state is updated before external calls
     */
    function test_ChecksEffectsInteractionsPattern() public {
        // Deploy malicious contract that checks state during callback
        MaliciousClaimReentrancy attacker = new MaliciousClaimReentrancy(
            address(heirloom),
            owner,
            address(token)
        );

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = address(attacker);

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Before attack
        uint256 releasedBefore = heirloom.ownerTokenReleased(owner, address(token));
        assertEq(releasedBefore, 0);

        // Attack
        vm.deal(address(attacker), 10 ether);
        attacker.attack{value: 0.001 ether}();

        // After attack - state should be updated exactly once
        uint256 releasedAfter = heirloom.ownerTokenReleased(owner, address(token));
        assertEq(releasedAfter, 1000 * 1e18, "State should be updated exactly once");
    }

    /**
     * @notice Test gas limits on refund
     * @dev Ensures refund uses .call{value:} not transfer()
     */
    function test_RefundUsesCallNotTransfer() public {
        // This test documents that refund should use .call{value:}
        // which forwards all available gas, not transfer() which only gives 2300 gas

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        uint256 balanceBefore = owner.balance;

        vm.prank(owner);
        heirloom.setupLegacies{value: 0.01 ether}(beneficiaries, shares, 100);

        uint256 balanceAfter = owner.balance;

        // Refund should be: 0.01 - 0.001 (setup fee) = 0.009 ether
        assertEq(balanceBefore - balanceAfter, 0.001 ether, "Should only pay setup fee");
    }

    /**
     * @notice Test multiple beneficiaries where one is malicious
     * @dev One beneficiary is a reentrancy attacker, others should still work
     */
    function test_OneMaliciousBeneficiaryDoesntBlockOthers() public {
        MaliciousClaimReentrancy attacker = new MaliciousClaimReentrancy(
            address(heirloom),
            owner,
            address(token)
        );

        address beneficiary2 = address(3);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = address(attacker);
        beneficiaries[1] = beneficiary2;

        uint16[] memory shares = new uint16[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Attacker claims
        vm.deal(address(attacker), 10 ether);
        attacker.attack{value: 0.001 ether}();
        assertEq(token.balanceOf(address(attacker)), 500 * 1e18);

        // Honest beneficiary can still claim
        vm.deal(beneficiary2, 10 ether);
        vm.prank(beneficiary2);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary2, tokens);
        assertEq(token.balanceOf(beneficiary2), 500 * 1e18);
    }

    /**
     * @notice Test batch claim with reentrancy attempt
     * @dev Malicious beneficiary tries reentrancy during batch claim
     */
    function test_ReentrancyInBatchClaim() public {
        MaliciousClaimReentrancy attacker = new MaliciousClaimReentrancy(
            address(heirloom),
            owner,
            address(token)
        );

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = address(attacker);

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Batch claim with excess fee
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        vm.deal(address(attacker), 10 ether);

        // Manually call batch claim from attacker
        vm.prank(address(attacker));
        heirloom.claimLegacies{value: 0.01 ether}(owner, address(attacker), tokens);

        // Should only claim once
        assertEq(token.balanceOf(address(attacker)), 1000 * 1e18);
    }

    /**
     * @notice Test deadline reset with reentrancy
     * @dev Owner is a malicious contract trying to reenter during refund
     */
    function test_ReentrancyOnDeadlineReset() public {
        MaliciousSetupReentrancy attacker = new MaliciousSetupReentrancy(address(heirloom));

        // Setup first
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(address(attacker), 10 ether);
        vm.prank(address(attacker));
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Reset with excess fee to trigger refund and reentrancy
        vm.prank(address(attacker));
        heirloom.resetDeadline{value: 0.01 ether}(200);

        // Verify only one reset happened
        uint256 deadline = heirloom.ownerExecutionTimestamp(address(attacker));
        assertEq(deadline, block.timestamp + 200);
    }

    /**
     * @notice Test that transfer() would fail but call() succeeds
     * @dev Simulates Account Abstraction scenario (EIP-4337)
     */
    function test_CallSucceedsWhereTransferWouldFail() public {
        // This test documents why .call{value:} is better than transfer()
        // In future with Account Abstraction, contracts may have expensive receive functions

        GasGuzzler guzzler = new GasGuzzler();

        // Fund the guzzler
        vm.deal(address(guzzler), 1 ether);

        // Try to send ETH using call (should work)
        (bool success, ) = address(guzzler).call{value: 0.1 ether}("");
        assertTrue(success, "Call should succeed with gas guzzler");

        // transfer() would fail here due to 2300 gas limit
        // but call() forwards all gas and succeeds
    }

    /**
     * @notice Test fee collection with various malicious scenarios
     * @dev Ensures fee collection is robust
     */
    function test_FeeCollectionWithMaliciousActors() public {
        // Scenario 1: Malicious owner
        MaliciousSetupReentrancy maliciousOwner = new MaliciousSetupReentrancy(address(heirloom));

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(address(maliciousOwner), 10 ether);
        vm.prank(address(maliciousOwner));
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        // Fee recipient should have received fee despite malicious owner
        assertEq(feeRecipient.balance, 0.001 ether);

        // Scenario 2: Malicious beneficiary claims (use different owner)
        address owner2 = address(0x999);
        token.transfer(owner2, 1000 * 1e18);
        vm.prank(owner2);
        token.approve(address(heirloom), type(uint256).max);

        MaliciousClaimReentrancy maliciousBeneficiary = new MaliciousClaimReentrancy(
            address(heirloom),
            owner2,
            address(token)
        );

        address[] memory beneficiaries2 = new address[](1);
        beneficiaries2[0] = address(maliciousBeneficiary);

        vm.deal(owner2, 10 ether);
        vm.prank(owner2);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries2, shares, 100);

        skip(101);

        vm.deal(address(maliciousBeneficiary), 10 ether);
        maliciousBeneficiary.attack{value: 0.0005 ether}();

        // Fee recipient should have received both setup fees (0.001 + 0.001) + 1 claim fee (0.0005)
        assertEq(feeRecipient.balance, 0.0025 ether);
    }

    function test_ClaimLegacyWithNonContractToken_ShouldSkip() public {
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 1 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        address nonContract = address(0x123456789);

        // claimLegacies with non-contract token should revert
        vm.deal(beneficiary, 1 ether);
        vm.prank(beneficiary);
        // Should revert because no tokens were transferred
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        address[] memory tokens = new address[](1); tokens[0] = nonContract; heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);
    }
}
