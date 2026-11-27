// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/EtherHeirloom.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FuzzToken is ERC20 {
    constructor() ERC20("Fuzz", "FZZ") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title Fuzz tests
 * @notice Property-based tests: the same rules are checked against thousands of random inputs
 *         (balances, shares, dates, fees, callers) instead of a few hand-picked values.
 */
contract Test18_Fuzz is Test {
    EtherHeirloom internal heirloom;
    FuzzToken internal token;

    address internal owner = makeAddr("owner");
    address internal heirA = makeAddr("heirA");
    address internal heirB = makeAddr("heirB");
    address internal feeRecipient = makeAddr("feeRecipient");

    uint256 internal constant SETUP_FEE = 0.003 ether;
    uint256 internal constant OPERATION_FEE = 0.001 ether;
    uint256 internal constant EXTENSION_FEE = 0.0005 ether;

    function setUp() public {
        heirloom = new EtherHeirloom(feeRecipient, SETUP_FEE, OPERATION_FEE, EXTENSION_FEE);
        token = new FuzzToken();
        vm.deal(owner, 100 ether);
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
    }

    function _tokens() internal view returns (address[] memory t) {
        t = new address[](1);
        t[0] = address(token);
    }

    function _setupTwo(uint16 shareA, uint256 delay) internal {
        address[] memory heirs = new address[](2);
        heirs[0] = heirA;
        heirs[1] = heirB;
        uint16[] memory shares = new uint16[](2);
        shares[0] = shareA;
        shares[1] = 10_000 - shareA;
        vm.prank(owner);
        heirloom.setupLegacies{value: SETUP_FEE}(heirs, shares, delay);
    }

    function _claim(address caller, address heir) internal {
        vm.deal(caller, 1 ether);
        vm.prank(caller);
        heirloom.claimLegacies{value: OPERATION_FEE}(owner, heir, _tokens());
    }

    /// Shares are accepted only when every share is non-zero and they add up to exactly 100%.
    function testFuzz_SharesMustSumToExactly100Percent(uint16[3] memory raw) public {
        address[] memory heirs = new address[](3);
        heirs[0] = heirA;
        heirs[1] = heirB;
        heirs[2] = makeAddr("heirC");
        uint16[] memory shares = new uint16[](3);
        uint256 sum;
        bool anyZeroOrTooBig;
        for (uint256 i; i < 3; ++i) {
            shares[i] = uint16(bound(raw[i], 0, 10_000));
            sum += shares[i];
            if (shares[i] == 0) anyZeroOrTooBig = true;
        }

        vm.prank(owner);
        if (anyZeroOrTooBig || sum != 10_000) {
            vm.expectRevert();
            heirloom.setupLegacies{value: SETUP_FEE}(heirs, shares, 1 days);
        } else {
            heirloom.setupLegacies{value: SETUP_FEE}(heirs, shares, 1 days);
            assertEq(heirloom.totalAllocatedShares(owner), 10_000);
        }
    }

    /// Nothing can be claimed before the date, whoever calls.
    function testFuzz_NoClaimBeforeTheDate(uint256 delay, uint256 waited, address caller) public {
        delay = bound(delay, 1, 100 * 365 days);
        waited = bound(waited, 0, delay - 1);
        vm.assume(caller != address(0) && caller.code.length == 0 && uint160(caller) > 0xff);
        token.mint(owner, 1_000e18);
        _setupTwo(5_000, delay);

        skip(waited);
        vm.deal(caller, 1 ether);
        vm.prank(caller);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        heirloom.claimLegacies{value: OPERATION_FEE}(owner, heirA, _tokens());
        assertEq(token.balanceOf(owner), 1_000e18);
    }

    /// After the date each heir receives exactly their share (rounded down); the owner keeps only rounding dust.
    function testFuzz_EachHeirGetsExactlyTheirShare(uint256 balance, uint16 shareA) public {
        balance = bound(balance, 1, 1e36);
        shareA = uint16(bound(shareA, 1, 9_999));
        token.mint(owner, balance);
        _setupTwo(shareA, 1 days);
        skip(1 days);

        uint256 dueA = (balance * shareA) / 10_000;
        uint256 dueB = (balance * (10_000 - shareA)) / 10_000;

        if (dueA > 0) _claim(heirA, heirA);
        if (dueB > 0) _claim(heirB, heirB);

        assertEq(token.balanceOf(heirA), dueA, "heir A");
        assertEq(token.balanceOf(heirB), dueB, "heir B");
        assertEq(token.balanceOf(owner), balance - dueA - dueB, "owner keeps dust only");
        assertLe(balance - dueA - dueB, 1, "dust is at most 1 unit for two heirs");
        assertEq(token.balanceOf(address(heirloom)), 0, "contract never holds tokens");
    }

    /// Anyone may trigger delivery, but the tokens always go to the listed heir, never to the caller.
    function testFuzz_DeliveryGoesToTheHeirNotTheCaller(address caller, uint256 balance) public {
        vm.assume(caller != address(0) && caller != heirA && caller != owner && caller.code.length == 0);
        vm.assume(uint160(caller) > 0xff);
        balance = bound(balance, 10_000, 1e30);
        token.mint(owner, balance);
        _setupTwo(4_000, 1 days);
        skip(1 days);

        uint256 callerBefore = token.balanceOf(caller);
        _claim(caller, heirA);
        assertEq(token.balanceOf(heirA), (balance * 4_000) / 10_000);
        assertEq(token.balanceOf(caller), callerBefore, "caller receives nothing");
    }

    /// An address that is not a listed heir can never receive anything.
    function testFuzz_NonHeirCannotClaim(address stranger) public {
        vm.assume(stranger != heirA && stranger != heirB && stranger != address(0));
        token.mint(owner, 1_000e18);
        _setupTwo(5_000, 1 days);
        skip(1 days);

        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(EtherHeirloom.NotBeneficiary.selector, owner, stranger));
        heirloom.claimLegacies{value: OPERATION_FEE}(owner, stranger, _tokens());
        assertEq(token.balanceOf(owner), 1_000e18);
    }

    /// Revoking the token approval stops all deliveries, even after the date.
    function testFuzz_RevokeStopsDelivery(uint256 balance, uint256 afterDate) public {
        balance = bound(balance, 1e6, 1e30);
        afterDate = bound(afterDate, 0, 50 * 365 days);
        token.mint(owner, balance);
        _setupTwo(5_000, 1 days);

        vm.prank(owner);
        token.approve(address(heirloom), 0);
        skip(1 days + afterDate);

        vm.deal(heirA, 1 ether);
        vm.prank(heirA);
        vm.expectRevert(EtherHeirloom.ClaimFailed.selector);
        heirloom.claimLegacies{value: OPERATION_FEE}(owner, heirA, _tokens());
        assertEq(token.balanceOf(owner), balance);
    }

    /// Moving the date later always blocks claims until the new date.
    function testFuzz_MovingTheDateBlocksClaims(uint256 firstDelay, uint256 newDelay) public {
        firstDelay = bound(firstDelay, 1, 365 days);
        newDelay = bound(newDelay, 1, 100 * 365 days);
        token.mint(owner, 1_000e18);
        _setupTwo(5_000, firstDelay);
        skip(firstDelay); // the first date has arrived

        vm.prank(owner);
        heirloom.resetDeadline{value: EXTENSION_FEE}(newDelay);

        vm.deal(heirA, 1 ether);
        vm.prank(heirA);
        vm.expectRevert(EtherHeirloom.ExecutionTimeNotReached.selector);
        heirloom.claimLegacies{value: OPERATION_FEE}(owner, heirA, _tokens());

        skip(newDelay);
        _claim(heirA, heirA);
        assertEq(token.balanceOf(heirA), 500e18);
    }

    /// Tokens that arrive after earlier deliveries are shared by the same percentages.
    function testFuzz_LaterIncomeIsSharedBySamePercentages(uint256 first, uint256 later, uint16 shareA) public {
        first = bound(first, 1e6, 1e30);
        later = bound(later, 1e6, 1e30);
        shareA = uint16(bound(shareA, 1, 9_999));
        token.mint(owner, first);
        _setupTwo(shareA, 1 days);
        skip(1 days);

        _claim(heirA, heirA);
        token.mint(owner, later);
        _claim(heirA, heirA);
        _claim(heirB, heirB);

        uint256 total = first + later;
        assertApproxEqAbs(token.balanceOf(heirA), (total * shareA) / 10_000, 1, "heir A over both deposits");
        assertApproxEqAbs(token.balanceOf(heirB), (total * (10_000 - shareA)) / 10_000, 1, "heir B over both deposits");
        assertLe(token.balanceOf(heirA) + token.balanceOf(heirB), total);
    }

    /// The fee recipient receives exactly the setup fee; any overpayment is refunded to the sender.
    function testFuzz_SetupFeeIsExactAndSurplusRefunded(uint256 paid) public {
        paid = bound(paid, SETUP_FEE, 50 ether);
        address[] memory heirs = new address[](1);
        heirs[0] = heirA;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10_000;

        uint256 ownerBefore = owner.balance;
        uint256 recipientBefore = feeRecipient.balance;
        vm.prank(owner);
        heirloom.setupLegacies{value: paid}(heirs, shares, 1 days);

        assertEq(feeRecipient.balance - recipientBefore, SETUP_FEE);
        assertEq(ownerBefore - owner.balance, SETUP_FEE);
        assertEq(address(heirloom).balance, 0, "contract never keeps ETH");
    }

    /// Paying less than the setup fee always fails.
    function testFuzz_UnderpaidSetupReverts(uint256 paid) public {
        paid = bound(paid, 0, SETUP_FEE - 1);
        address[] memory heirs = new address[](1);
        heirs[0] = heirA;
        uint16[] memory shares = new uint16[](1);
        shares[0] = 10_000;
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(EtherHeirloom.InsufficientFee.selector, SETUP_FEE, paid));
        heirloom.setupLegacies{value: paid}(heirs, shares, 1 days);
    }
}
