// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../contracts/EtherHeirloom.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract InvariantToken is ERC20 {
    constructor() ERC20("Invariant", "INV") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @notice Drives random sequences of real user actions against one owner's plan:
 *         set up or change the plan, move the date, revoke or restore the approval,
 *         receive or spend tokens, let time pass, and deliver to random heirs from random callers.
 */
contract HeirloomHandler is Test {
    EtherHeirloom public heirloom;
    InvariantToken public token;
    address public owner;
    address public feeRecipient;
    address[] public heirs;
    address[] public callers;

    /// Ghost accounting kept by the test itself
    mapping(address => uint256) public receivedByHeir;
    uint256 public totalDelivered;
    uint256 public prematureDeliveries;
    uint256 public deliveriesToNonHeirs;
    uint256 public callerGains;

    uint256 internal constant OPERATION_FEE = 0.001 ether;
    uint256 internal constant SETUP_FEE = 0.003 ether;
    uint256 internal constant EXTENSION_FEE = 0.0005 ether;

    constructor(EtherHeirloom _heirloom, InvariantToken _token, address _owner, address _feeRecipient) {
        heirloom = _heirloom;
        token = _token;
        owner = _owner;
        feeRecipient = _feeRecipient;
        for (uint256 i; i < 4; ++i) heirs.push(makeAddr(string.concat("heir", vm.toString(i))));
        for (uint256 i; i < 3; ++i) callers.push(makeAddr(string.concat("caller", vm.toString(i))));
    }

    function heirCount() external view returns (uint256) {
        return heirs.length;
    }

    function setupPlan(uint256 count, uint256 seed, uint256 delay) external {
        count = bound(count, 1, heirs.length);
        delay = bound(delay, 0, 30 days);
        address[] memory list = new address[](count);
        uint16[] memory shares = new uint16[](count);
        uint256 remaining = 10_000;
        for (uint256 i; i < count; ++i) {
            list[i] = heirs[(seed + i) % heirs.length];
            if (i == count - 1) {
                shares[i] = uint16(remaining);
            } else {
                uint256 maxForThis = remaining - (count - 1 - i); // leave at least 1 for each remaining heir
                uint256 s = bound(uint256(keccak256(abi.encode(seed, i))), 1, maxForThis);
                shares[i] = uint16(s);
                remaining -= s;
            }
        }
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        heirloom.setupLegacies{value: SETUP_FEE}(list, shares, delay);
    }

    function moveDate(uint256 delay) external {
        delay = bound(delay, 0, 30 days);
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        heirloom.resetDeadline{value: EXTENSION_FEE}(delay);
    }

    function setApproval(bool on) external {
        vm.prank(owner);
        token.approve(address(heirloom), on ? type(uint256).max : 0);
    }

    function ownerReceives(uint256 amount) external {
        token.mint(owner, bound(amount, 0, 1e30));
    }

    function ownerSpends(uint256 amount) external {
        uint256 bal = token.balanceOf(owner);
        amount = bound(amount, 0, bal);
        vm.prank(owner);
        token.transfer(address(0xdead), amount);
    }

    function passTime(uint256 secs) external {
        skip(bound(secs, 0, 40 days));
    }

    function deliver(uint256 heirSeed, uint256 callerSeed) external {
        address heir = heirs[heirSeed % heirs.length];
        address caller = callers[callerSeed % callers.length];
        address[] memory t = new address[](1);
        t[0] = address(token);

        uint256 heirBefore = token.balanceOf(heir);
        uint256 callerBefore = token.balanceOf(caller);
        uint256 ownerBefore = token.balanceOf(owner);
        bool beforeDate = block.timestamp < heirloom.ownerExecutionTimestamp(owner);

        vm.deal(caller, 1 ether);
        vm.prank(caller);
        try heirloom.claimLegacies{value: OPERATION_FEE}(owner, heir, t) {
            uint256 got = token.balanceOf(heir) - heirBefore;
            receivedByHeir[heir] += got;
            totalDelivered += got;
            if (beforeDate) prematureDeliveries++;
            if (ownerBefore - token.balanceOf(owner) != got) deliveriesToNonHeirs++;
        } catch {}

        if (token.balanceOf(caller) > callerBefore) callerGains++;
    }
}

/**
 * @title Invariant tests
 * @notice Rules that must hold after every step of thousands of random action sequences.
 */
contract Test19_Invariants is StdInvariant, Test {
    EtherHeirloom internal heirloom;
    InvariantToken internal token;
    HeirloomHandler internal handler;
    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        heirloom = new EtherHeirloom(feeRecipient, 0.003 ether, 0.001 ether, 0.0005 ether);
        token = new InvariantToken();
        handler = new HeirloomHandler(heirloom, token, owner, feeRecipient);
        token.mint(owner, 1_000_000e18);
        vm.prank(owner);
        token.approve(address(heirloom), type(uint256).max);
        targetContract(address(handler));
    }

    /// The contract never holds anyone's tokens: they stay in the owner's wallet until delivered.
    function invariant_ContractNeverHoldsTokens() public view {
        assertEq(token.balanceOf(address(heirloom)), 0);
    }

    /// The contract never keeps ETH: fees are forwarded and surplus is refunded in the same transaction.
    function invariant_ContractNeverHoldsEth() public view {
        assertEq(address(heirloom).balance, 0);
    }

    /// A plan is either empty or allocates exactly 100%.
    function invariant_SharesAreZeroOrExactly100Percent() public view {
        uint256 total = heirloom.totalAllocatedShares(owner);
        assertTrue(total == 0 || total == 10_000);
    }

    /// Nothing is ever delivered before the date.
    function invariant_NoDeliveryBeforeTheDate() public view {
        assertEq(handler.prematureDeliveries(), 0);
    }

    /// Every token that leaves the owner's wallet through the contract lands with the heir it was claimed for,
    /// and the caller who triggered the delivery never receives anything.
    function invariant_TokensOnlyGoToHeirs() public view {
        assertEq(handler.deliveriesToNonHeirs(), 0);
        assertEq(handler.callerGains(), 0);
    }

    /// The contract's own record of delivered tokens matches what the heirs actually received.
    function invariant_RecordedDeliveriesMatchReality() public view {
        uint256 recordedPerHeir;
        for (uint256 i; i < handler.heirCount(); ++i) {
            address heir = handler.heirs(i);
            uint256 recorded = heirloom.beneficiaryClaims(owner, heir, address(token));
            assertEq(recorded, handler.receivedByHeir(heir), "per-heir record");
            assertEq(token.balanceOf(heir), recorded, "heir balance equals delivered amount");
            recordedPerHeir += recorded;
        }
        assertEq(heirloom.ownerTokenReleased(owner, address(token)), recordedPerHeir, "total released");
        assertEq(handler.totalDelivered(), recordedPerHeir, "ghost total");
    }
}
