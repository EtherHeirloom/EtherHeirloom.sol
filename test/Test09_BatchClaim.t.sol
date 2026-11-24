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

contract BadToken is ERC20 {
    bool public shouldFail;

    constructor() ERC20("Bad", "BAD") {
        _mint(msg.sender, 1000000 * 1e18);
    }

    function setFail(bool _fail) external {
        shouldFail = _fail;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false; // Return false instead of reverting for batch claim to work
        }
        return super.transferFrom(from, to, amount);
    }
}

contract PausableToken is ERC20 {
    bool public paused;

    constructor() ERC20("Pausable", "PAUSE") {
        _mint(msg.sender, 1000000 * 1e18);
    }

    function pause() external {
        paused = true;
    }

    function unpause() external {
        paused = false;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (paused) {
            return false; // Return false instead of reverting for batch claim to work
        }
        return super.transferFrom(from, to, amount);
    }
}

/**
 * @title Test 9: Batch Claim with Failing Tokens Edge Case
 * @notice Tests that batch claim skips failing tokens without reverting entire transaction
 * @dev Scenario: Beneficiary claims 20 tokens, one is blocked/scam, others succeed
 */
contract Test09_BatchClaim is Test {
    EtherHeirloom public heirloom;
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;
    BadToken public badToken;
    PausableToken public pausableToken;

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
        token1 = new MockToken();
        token2 = new MockToken();
        token3 = new MockToken();
        badToken = new BadToken();
        pausableToken = new PausableToken();

        // Transfer tokens to owner
        token1.transfer(owner, 1000 * 1e18);
        token2.transfer(owner, 1000 * 1e18);
        token3.transfer(owner, 1000 * 1e18);
        badToken.transfer(owner, 1000 * 1e18);
        pausableToken.transfer(owner, 1000 * 1e18);

        // Owner approves all tokens
        vm.startPrank(owner);
        token1.approve(address(heirloom), type(uint256).max);
        token2.approve(address(heirloom), type(uint256).max);
        token3.approve(address(heirloom), type(uint256).max);
        badToken.approve(address(heirloom), type(uint256).max);
        pausableToken.approve(address(heirloom), type(uint256).max);
        vm.stopPrank();
    }

    function test_BatchClaimAllSuccess() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000; // 100%

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Batch claim 3 tokens
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0015 ether}(owner, beneficiary, tokens);

        // All tokens transferred
        assertEq(token1.balanceOf(beneficiary), 1000 * 1e18);
        assertEq(token2.balanceOf(beneficiary), 1000 * 1e18);
        assertEq(token3.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_BatchClaimWithOneFailing() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Make badToken fail - SafeERC20 will revert on false return
        badToken.setFail(true);

        // Batch claim including bad token - should revert due to SafeERC20
        address[] memory tokens = new address[](4);
        tokens[0] = address(token1);
        tokens[1] = address(badToken); // This will revert
        tokens[2] = address(token2);
        tokens[3] = address(token3);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        // SafeERC20 reverts on false return, so entire batch fails
        vm.expectRevert();
        heirloom.claimLegacies{value: 0.002 ether}(owner, beneficiary, tokens);
    }

    function test_BatchClaimWithPausedToken() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Pause the pausable token
        pausableToken.pause();

        // Batch claim - SafeERC20 will revert on false return
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(pausableToken); // Paused - will revert
        tokens[2] = address(token2);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        // SafeERC20 reverts on false return
        vm.expectRevert();
        heirloom.claimLegacies{value: 0.0015 ether}(owner, beneficiary, tokens);
    }

    function test_BatchClaimAllFailing() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Make badToken fail
        badToken.setFail(true);
        pausableToken.pause();

        // Batch claim only failing tokens - SafeERC20 will revert
        address[] memory tokens = new address[](2);
        tokens[0] = address(badToken);
        tokens[1] = address(pausableToken);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        // SafeERC20 reverts on false return
        vm.expectRevert();
        heirloom.claimLegacies{value: 0.001 ether}(owner, beneficiary, tokens);
    }

    function test_BatchClaimExceedsMaxLimit() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Try to claim 11 tokens (exceeds MAX_BATCH_TOKENS = 10)
        address[] memory tokens = new address[](11);
        for (uint i = 0; i < 11; i++) {
            tokens[i] = address(token1); // Reuse same token for simplicity
        }

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.InvalidArrayLength.selector);
        heirloom.claimLegacies{value: 0.0055 ether}(owner, beneficiary, tokens);
    }

    function test_BatchClaimEmptyArray() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Try to claim empty array
        address[] memory tokens = new address[](0);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        vm.expectRevert(EtherHeirloom.InvalidArrayLength.selector);
        heirloom.claimLegacies{value: 0}(owner, beneficiary, tokens);
    }

    function test_BatchClaimSingleToken() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Batch claim with single token
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        assertEq(token1.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_BatchClaimWithZeroBalance() public {
        // Setup legacy but owner has no tokens
        vm.prank(owner);
        token1.transfer(address(0xdead), 1000 * 1e18);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Batch claim tokens with zero balance
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1); // Zero balance
        tokens[1] = address(token2); // Has balance

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.001 ether}(owner, beneficiary, tokens);

        // Only token2 transferred
        assertEq(token1.balanceOf(beneficiary), 0);
        assertEq(token2.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_BatchClaimRefundsUnusedFees() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Make badToken fail
        badToken.setFail(true);

        // Batch claim 3 tokens, but one will fail - SafeERC20 will revert entire batch
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(badToken); // Will revert entire batch
        tokens[2] = address(token2);

        vm.deal(beneficiary, 10 ether);

        vm.prank(beneficiary);
        // SafeERC20 reverts on false return, entire batch fails
        vm.expectRevert();
        heirloom.claimLegacies{value: 0.0015 ether}(owner, beneficiary, tokens);
    }

    function test_BatchClaimMaxTokens() public {
        // Create 10 mock tokens (MAX_BATCH_TOKENS)
        MockToken[10] memory tokens;
        for (uint i = 0; i < 10; i++) {
            tokens[i] = new MockToken();
            tokens[i].transfer(owner, 1000 * 1e18);
            vm.prank(owner);
            tokens[i].approve(address(heirloom), type(uint256).max);
        }

        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Batch claim exactly 10 tokens
        address[] memory tokenAddresses = new address[](10);
        for (uint i = 0; i < 10; i++) {
            tokenAddresses[i] = address(tokens[i]);
        }

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.005 ether}(owner, beneficiary, tokenAddresses);

        // All tokens transferred
        for (uint i = 0; i < 10; i++) {
            assertEq(tokens[i].balanceOf(beneficiary), 1000 * 1e18);
        }
    }

    function test_BatchClaimWithInsufficientFee() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Try batch claim with insufficient fee (fee is now per-transaction, not per-token)
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        // Fee is 0.0005 ether per transaction (flat fee regardless of token count)
        vm.expectRevert(abi.encodeWithSelector(EtherHeirloom.InsufficientFee.selector, 0.0005 ether, 0.0004 ether));
        heirloom.claimLegacies{value: 0.0004 ether}(owner, beneficiary, tokens); // Need 0.0005
    }

    function test_BatchClaimSameTokenTwice() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Try to claim same token twice in one batch
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token1); // Duplicate

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        heirloom.claimLegacies{value: 0.001 ether}(owner, beneficiary, tokens);

        // First claim succeeds, second should fail (nothing left to claim)
        assertEq(token1.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_BatchClaimWithNonContractToken() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        // Batch claim including an EOA address (non-contract)
        address eoa = address(0x555);
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = eoa; // EOA - should be skipped efficiently
        tokens[2] = address(token2);

        vm.deal(beneficiary, 10 ether);
        vm.prank(beneficiary);
        // Should succeed and skip the EOA
        heirloom.claimLegacies{value: 0.0015 ether}(owner, beneficiary, tokens);

        // Both legitimate tokens should have been transferred
        assertEq(token1.balanceOf(beneficiary), 1000 * 1e18);
        assertEq(token2.balanceOf(beneficiary), 1000 * 1e18);
    }

    function test_ThirdPartyClaim() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        address thirdParty = address(0x999);
        vm.deal(thirdParty, 10 ether);
        uint256 thirdPartyBalanceBefore = thirdParty.balance;

        // Third party calls claim for beneficiary
        vm.prank(thirdParty);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Token should go to beneficiary, not third party
        assertEq(token1.balanceOf(beneficiary), 1000 * 1e18);
        assertEq(token1.balanceOf(thirdParty), 0);

        // Third party should have paid the fee
        // Balance = Start - Fee
        assertEq(thirdParty.balance, thirdPartyBalanceBefore - 0.0005 ether);
    }

    function test_AttackerCannotRedirectFunds() public {
        // Setup legacy
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = beneficiary;

        uint16[] memory shares = new uint16[](1);
        shares[0] = 10000;

        vm.deal(owner, 10 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: 0.001 ether}(beneficiaries, shares, 100);

        skip(101);

        address attacker = address(0x666);
        vm.deal(attacker, 10 ether);

        // Attacker tries to claim for themselves (passing themselves as beneficiary arg)
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(EtherHeirloom.NotBeneficiary.selector, owner, attacker));
        address[] memory tokens = new address[](1);
        tokens[0] = address(token1);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, attacker, tokens);

        // Attacker tries to call claimLegacy with valid args but expects funds to come to msg.sender
        vm.prank(attacker);
        heirloom.claimLegacies{value: 0.0005 ether}(owner, beneficiary, tokens);

        // Funds should go to beneficiary, NOT attacker
        assertEq(token1.balanceOf(beneficiary), 1000 * 1e18);
        assertEq(token1.balanceOf(attacker), 0);
    }
}
