// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title EtherHeirloom
 * @author EtherHeirloom Team
 * @notice Protocol for secure, non-custodial asset inheritance with share-based distribution and unified deadlines.
 * @dev All fees are immutable. This ensures a "contract is law" guarantee for the owner and beneficiaries.
 */
contract EtherHeirloom is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LegacyAccount {
        address owner;
        address beneficiary;
        uint64 beneficiaryIndex; // Index in the beneficiaryOwners list
        uint64 ownerIndex;       // Index in the ownerBeneficiaries list
        uint16 share;           // Percentage in Basis Points (10000 = 100%)
        bool isActive;
    }
    /// @notice Custom Errors for gas optimization and clarity
    error NotBeneficiary(address owner, address caller);
    error InvalidFeeRecipient();
    error OnlyProtocolRecipient();
    error InvalidRecipientAddress();
    error NoBeneficiariesProvided();
    error TooManyBeneficiaries();
    error MismatchedInputs();
    error InsufficientFee(uint256 required, uint256 provided);
    error InvalidSender();
    error OwnerCannotBeBeneficiary();
    error InvalidBeneficiaryAddress();
    error DuplicateBeneficiary(address beneficiary);
    error InvalidShare();
    error TotalSharesMismatch();
    error FeeTransferFailed();
    error RefundFailed();
    error OwnerMismatch();
    error LegacyNotActive();
    error ExecutionTimeNotReached();
    error InvalidArrayLength();
    error ClaimFailed();

    /// @notice Mapping from Owner -> Beneficiary -> Legacy Account
    mapping(address => mapping(address => LegacyAccount)) private _legacies;

    /// @notice Mapping from Owner to list of their Beneficiaries
    mapping(address => address[]) private ownerBeneficiaries;

    /// @notice Mapping from Beneficiary to a list of Owners who set up legacies for them
    mapping(address => address[]) private beneficiaryOwners;

    /// @notice Track total allocated percentage per owner to prevent over-allocation (Basis Points)
    mapping(address => uint256) public totalAllocatedShares;

    /// @notice Global Execution Timestamp for the Owner (Unified Deadline)
    mapping(address => uint256) public ownerExecutionTimestamp;

    /// @notice Virtual Pool Tracking: Owner -> Token -> Total Released Amount
    mapping(address => mapping(address => uint256)) public ownerTokenReleased;

    /// @notice Owner -> Beneficiary -> Token -> Total Claimed Amount
    mapping(address => mapping(address => mapping(address => uint256))) public beneficiaryClaims;

    /// @notice One-time setup fee for a legacy plan (in Wei)
    uint256 public immutable setupFee;

    /// @notice Operation fee for each claim/withdrawal (in Wei)
    uint256 public immutable operationFee;

    /// @notice Fee for extending or resetting the deadline (in Wei)
    uint256 public immutable deadlineExtensionFee;

    /// @notice 100.00% in Basis Points
    uint16 public constant MAX_SHARE = 1e4;

    /// @notice Maximum number of beneficiaries per owner (DoS protection)
    uint256 public constant MAX_BENEFICIARIES = 10;

    /// @notice Maximum number of tokens per batch claim (Gas limit protection)
    uint256 public constant MAX_BATCH_TOKENS = 10;

    /// @notice Address entitled to collect protocol fees
    address public protocolFeeRecipient;

    /**
     * @notice Emitted when a legacy is set up or updated.
     * @param owner The address of the legacy creator.
     * @param beneficiary The address of the heir.
     * @param executionTimestamp The time after which assets become claimable (indexed).
     * @param share The allocation in basis points (indexed).
     */
    event LegacySetup(address indexed owner, address indexed beneficiary, uint256 indexed executionTimestamp, uint16 share);

    /**
     * @notice Emitted when an owner resets their deadline.
     * @param owner The address of the owner (indexed).
     * @param newExecutionTimestamp The updated claimable timestamp (indexed).
     */
    event DeadlineReset(address indexed owner, uint256 indexed newExecutionTimestamp);

    /**
     * @notice Emitted when an heir successfully claims assets.
     * @param owner The address of the owner.
     * @param beneficiary The address of the heir.
     * @param token The address of the ERC-20 token.
     * @param amount The amount of tokens transferred.
     */
    event LegacyClaimed(address indexed owner, address indexed beneficiary, address indexed token, uint256 amount);

    /**
     * @notice Emitted when a legacy configuration is removed.
     * @param owner The address of the owner.
     * @param beneficiary The address of the heir.
     */
    event LegacyCancelled(address indexed owner, address indexed beneficiary);

    /**
     * @notice Emitted when the protocol fee recipient is updated.
     * @param oldRecipient The previous recipient address.
     * @param newRecipient The new recipient address.
     */
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    /**
     * @notice Emitted when a service fee is collected by the protocol.
     * @param payer The address of the user who paid the fee.
     * @param amount The amount of fees collected (indexed).
     */
    event FeeCollected(address indexed payer, uint256 indexed amount);

    /**
     * @notice Emitted when a legacy becomes active in the system.
     * @param owner The address of the owner.
     * @param beneficiary The address of the heir.
     */
    event HeirloomActived(address indexed owner, address indexed beneficiary);

    /**
     * @notice Constructor to initialize the protocol.
     * @param _feeRecipient The address that will receive protocol fees.
     * @param _setupFee The fee for setting up legacies (in Wei).
     * @param _operationFee The fee for claim operations (in Wei).
     * @param _deadlineExtensionFee The fee for extending deadlines (in Wei).
     */
    constructor(
        address _feeRecipient,
        uint256 _setupFee,
        uint256 _operationFee,
        uint256 _deadlineExtensionFee
    ) {
        if (_feeRecipient == address(0)) revert InvalidFeeRecipient();

        protocolFeeRecipient = _feeRecipient;
        setupFee = _setupFee;
        operationFee = _operationFee;
        deadlineExtensionFee = _deadlineExtensionFee;
    }

    /**
     * @notice Updates the protocol fee recipient address.
     * @param _newRecipient The new address to receive protocol fees.
     */
    function updateFeeRecipient(address _newRecipient) external {
        if (msg.sender != protocolFeeRecipient) revert OnlyProtocolRecipient();
        if (_newRecipient == address(0)) revert InvalidRecipientAddress();

        address oldRecipient = protocolFeeRecipient;
        protocolFeeRecipient = _newRecipient;

        emit FeeRecipientUpdated(oldRecipient, _newRecipient);
    }

    /**
     * @notice Setups legacies for multiple beneficiaries in one transaction.
     * @dev AI Agents: Use this function when a user wants to establish an inheritance plan.
     * It requires a list of beneficiaries, their percentage shares (in basis points), and a delay period.
     * Total shares must equal 10000 (100%).
     * @param _beneficiaries Array of beneficiary addresses.
     * @param _shares Array of shares in basis points (100 = 1%).
     * @param _delaySeconds Delay in seconds before legacies can be claimed after owner's last proof of life.
     */
    function setupLegacies(address[] calldata _beneficiaries, uint16[] calldata _shares, uint256 _delaySeconds) external payable nonReentrant {
        // Input validation: Check lengths, payment and addresses first
        if (_beneficiaries.length == 0) revert NoBeneficiariesProvided();
        if (_beneficiaries.length > MAX_BENEFICIARIES) revert TooManyBeneficiaries();
        if (_beneficiaries.length != _shares.length) revert MismatchedInputs();
        if (msg.value < setupFee) revert InsufficientFee(setupFee, msg.value);
        if (protocolFeeRecipient == address(0)) revert InvalidFeeRecipient();
        if (msg.sender == address(0)) revert InvalidSender();

        // Check for duplicate addresses and self-inheritance to prevent logical errors
        for (uint256 i = 0; i < _beneficiaries.length; ++i) {
            if (_beneficiaries[i] == msg.sender) revert OwnerCannotBeBeneficiary();
            if (_beneficiaries[i] == address(0)) revert InvalidBeneficiaryAddress();
            for (uint256 j = i + 1; j < _beneficiaries.length; ++j) {
                if (_beneficiaries[i] == _beneficiaries[j]) revert DuplicateBeneficiary(_beneficiaries[i]);
            }
        }

        // 1. Wipe current configuration to allow fresh start
        address[] storage current = ownerBeneficiaries[msg.sender];
        while (current.length > 0) {
            _removeLegacy(msg.sender, current[current.length - 1]);
        }
        totalAllocatedShares[msg.sender] = 0;

        // 2. Set unified execution timestamp
        ownerExecutionTimestamp[msg.sender] = block.timestamp + _delaySeconds;

        for (uint256 i = 0; i < _beneficiaries.length; ++i) {
            _setupLegacyInternal(_beneficiaries[i], _shares[i]);
        }

        if (totalAllocatedShares[msg.sender] != MAX_SHARE) revert TotalSharesMismatch();

        // 3. Keep exactly setupFee, refund any surplus msg.value
        (bool success, ) = payable(protocolFeeRecipient).call{value: setupFee}("");
        if (!success) revert FeeTransferFailed();

        uint256 refund = msg.value - setupFee;
        if (refund > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refund}("");
            if (!refundSuccess) revert RefundFailed();
        }
    }

    /**
     * @notice Internal helper to set up a single legacy account.
     * @param _beneficiary The address of the heir.
     * @param _share The share in basis points (10000 = 100%).
     */
    function _setupLegacyInternal(address _beneficiary, uint16 _share) internal {
        if (_beneficiary == address(0)) revert InvalidBeneficiaryAddress();
        if (_share == 0 || _share > MAX_SHARE) revert InvalidShare();

        LegacyAccount storage legacy = _legacies[msg.sender][_beneficiary];
        // Note: No more intermediate share limit check here, because we wipe first and check at end of setupLegacies.

        if (!legacy.isActive) {
             // Add to tracking lists
             uint256 bIndex = beneficiaryOwners[_beneficiary].length;
             beneficiaryOwners[_beneficiary].push(msg.sender);

             uint256 oIndex = ownerBeneficiaries[msg.sender].length;
             ownerBeneficiaries[msg.sender].push(_beneficiary);

             legacy.owner = msg.sender;
             legacy.beneficiary = _beneficiary;
             legacy.beneficiaryIndex = SafeCast.toUint64(bIndex);
             legacy.ownerIndex = SafeCast.toUint64(oIndex);
             legacy.isActive = true;

             emit HeirloomActived(msg.sender, _beneficiary);
        }

        totalAllocatedShares[msg.sender] += _share;
        legacy.share = _share;
        emit LegacySetup(msg.sender, _beneficiary, ownerExecutionTimestamp[msg.sender], _share);
    }

    /**
     * @notice Internal helper to deactivate a legacy.
     * @param _owner The address of the legacy owner.
     * @param _beneficiary The address of the heir.
     */
    function _removeLegacy(address _owner, address _beneficiary) internal {
        LegacyAccount storage legacy = _legacies[_owner][_beneficiary];
        if (!legacy.isActive) return;

        _removeFromTrackingLists(_owner, _beneficiary);
        legacy.isActive = false;
        legacy.share = 0;
        // Legacy data remains in storage to ensure continuity if re-added
    }

    /**
     * @notice Internal helper to update tracking lists after removal.
     * @param _owner Address of the owner.
     * @param _beneficiary Address of the heir removed.
     */
    function _removeFromTrackingLists(address _owner, address _beneficiary) internal {
        // Remove from beneficiary's list of owners
        uint256 bIndex = _legacies[_owner][_beneficiary].beneficiaryIndex;
        uint256 bLastIndex = beneficiaryOwners[_beneficiary].length - 1;

        if (uint256(bIndex) != bLastIndex) {
            address lastOwner = beneficiaryOwners[_beneficiary][bLastIndex];
            beneficiaryOwners[_beneficiary][uint256(bIndex)] = lastOwner;
            _legacies[lastOwner][_beneficiary].beneficiaryIndex = SafeCast.toUint64(bIndex);
        }
        beneficiaryOwners[_beneficiary].pop();

        // Remove from owner's list of beneficiaries
        uint256 oIndex = _legacies[_owner][_beneficiary].ownerIndex;
        uint256 oLastIndex = ownerBeneficiaries[_owner].length - 1;

        if (uint256(oIndex) != oLastIndex) {
            address lastBeneficiary = ownerBeneficiaries[_owner][oLastIndex];
            ownerBeneficiaries[_owner][uint256(oIndex)] = lastBeneficiary;
            _legacies[_owner][lastBeneficiary].ownerIndex = SafeCast.toUint64(oIndex);
        }
        ownerBeneficiaries[_owner].pop();
    }

    /**
     * @notice Allows an owner to prove they are alive by resetting the execution deadline
     * @dev AI Agents: This is a "heartbeat" function. It MUST be called periodically by the owner
     * to prevent the inheritance from becoming claimable. If the deadline passes without a reset,
     * beneficiaries can start claiming assets.
     * @param _newDelaySeconds The new delay in seconds from the current time
     */
    function resetDeadline(uint256 _newDelaySeconds) external payable nonReentrant {
        // Input validation: Check payment first
        if (msg.value < deadlineExtensionFee) revert InsufficientFee(deadlineExtensionFee, msg.value);
        if (protocolFeeRecipient == address(0)) revert InvalidFeeRecipient();

        // Effects: Update state first (follow CEI pattern)
        ownerExecutionTimestamp[msg.sender] = block.timestamp + _newDelaySeconds;
        emit DeadlineReset(msg.sender, ownerExecutionTimestamp[msg.sender]);

        // Interactions: Transfer fee after state changes
        (bool success, ) = payable(protocolFeeRecipient).call{value: deadlineExtensionFee}("");
        if (!success) revert FeeTransferFailed();
        emit FeeCollected(msg.sender, deadlineExtensionFee);

        // Refund any surplus
        uint256 refund = msg.value - deadlineExtensionFee;
        if (refund > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refund}("");
            if (!refundSuccess) revert RefundFailed();
        }
    }

    /**
     * @notice Allows a beneficiary to claim legacies for one or multiple tokens in a single transaction
     * @dev AI Agents: This function triggers the transfer of inherited assets. It can only be
     * successfully called AFTER the owner's deadline has passed. The caller must pay a small operation fee.
     * Assets are transferred from the owner's address to the beneficiary based on the predefined shares.
     * Fee is charged per transaction (not per token). Reverts if no tokens were successfully transferred.
     * @param _owner The address of the legacy owner
     * @param _beneficiary The address of the beneficiary
     * @param _tokens An array of token addresses to claim (use single-element array for single token)
     */
    function claimLegacies(address _owner, address _beneficiary, address[] calldata _tokens) external payable nonReentrant {
        // Input validation: Check lengths, payment and addresses first
        if (_tokens.length == 0 || _tokens.length > MAX_BATCH_TOKENS) revert InvalidArrayLength();
        if (msg.value < operationFee) revert InsufficientFee(operationFee, msg.value);
        if (protocolFeeRecipient == address(0)) revert InvalidFeeRecipient();
        if (msg.sender == address(0)) revert InvalidSender();

        uint256 processedCount = 0;
        for (uint256 i = 0; i < _tokens.length; ++i) {
            if (_claimInternal(_owner, _beneficiary, _tokens[i])) {
                ++processedCount;
            }
        }

        if (processedCount == 0) revert ClaimFailed();

        // Fee is charged per transaction (we know at least one token was transferred)
        (bool success, ) = payable(protocolFeeRecipient).call{value: operationFee}("");
        if (!success) revert FeeTransferFailed();
        emit FeeCollected(msg.sender, operationFee);

        // --- Immediate Refund of surplus ETH ---
        uint256 refund = msg.value - operationFee;
        if (refund > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refund}("");
            if (!refundSuccess) revert RefundFailed();
        }
    }

    /**
     * @notice Internal helper to validate a claim and calculate the payment amount.
     * @param _owner The address of the legacy owner.
     * @param _beneficiary The address of the beneficiary.
     * @param _token The address of the token being claimed.
     * @return Success status (true if tokens were transferred).
     */
    function _claimInternal(address _owner, address _beneficiary, address _token) internal returns (bool) {
        LegacyAccount storage legacy = _legacies[_owner][_beneficiary];
        if (legacy.beneficiary == address(0)) revert NotBeneficiary(_owner, _beneficiary);

        if (_token.code.length == 0) {
            return false;
        }

        if (legacy.owner != _owner) revert OwnerMismatch();
        if (!legacy.isActive) revert LegacyNotActive();
        if (block.timestamp < ownerExecutionTimestamp[_owner]) revert ExecutionTimeNotReached();

        uint256 payment;
        IERC20 token = IERC20(_token);

        {
            uint256 currentBalance = token.balanceOf(_owner);
            uint256 virtualPool = currentBalance + ownerTokenReleased[_owner][_token];
            uint256 paymentDue = (virtualPool * uint256(legacy.share)) / MAX_SHARE;
            uint256 alreadyClaimed = beneficiaryClaims[_owner][_beneficiary][_token];

            if (paymentDue == alreadyClaimed || paymentDue < alreadyClaimed) {
                return false;
            }

            uint256 idealPayment = paymentDue - alreadyClaimed;
            uint256 allowance = token.allowance(_owner, address(this));
            uint256 available = currentBalance < allowance ? currentBalance : allowance;

            payment = available < idealPayment ? available : idealPayment;
        }

        if (payment == 0) {
            return false;
        }

        return _executeTransfer(_owner, _token, payment, legacy);
    }

    /**
     * @notice Internal helper to perform token transfer and state updates.
     * @param _owner Address of the owner.
     * @param _token Address of the token.
     * @param _payment Amount of tokens determined as claimable.
     * @param _legacy storage reference to the legacy account.
     * @return Success status.
     */
    function _executeTransfer(
        address _owner,
        address _token,
        uint256 _payment,
        LegacyAccount storage _legacy
    ) internal returns (bool) {
        IERC20 token = IERC20(_token);
        // Measure actual transfer amount to handle fee-on-transfer tokens
        address actualOwner = _legacy.owner;
        address actualBeneficiary = _legacy.beneficiary;

        // Record beneficiary balance before transfer
        uint256 beneficiaryBalanceBefore = token.balanceOf(actualBeneficiary);

        // Transfer using SafeERC20
        token.safeTransferFrom(actualOwner, actualBeneficiary, _payment);

        // Record beneficiary balance after transfer
        uint256 beneficiaryBalanceAfter = token.balanceOf(actualBeneficiary);

        // Calculate actual amount received (handles fee-on-transfer tokens)
        uint256 actualReceived = beneficiaryBalanceAfter - beneficiaryBalanceBefore;

        // Update state with ACTUAL received amount, not requested amount
        // This ensures virtual pool accounting remains accurate for fee-on-transfer tokens
        beneficiaryClaims[_owner][actualBeneficiary][_token] += actualReceived;
        ownerTokenReleased[_owner][_token] += actualReceived;

        emit LegacyClaimed(actualOwner, actualBeneficiary, _token, actualReceived);

        return true;
    }

    /**
     * @notice Returns legacies set up for a specific beneficiary with pagination support.
     * @param _beneficiary The address of the heir to query.
     * @param _offset The starting index for pagination (0-based).
     * @param _limit The maximum number of records to return (use 50 as default).
     * @return List of LegacyAccount structures (paginated).
     */
    function getHeirloomsForBeneficiary(
        address _beneficiary,
        uint256 _offset,
        uint256 _limit
    ) external view returns (LegacyAccount[] memory) {
        address[] memory owners = beneficiaryOwners[_beneficiary];
        if (owners.length == 0 || _offset > owners.length - 1 || _limit == 0) {
            return new LegacyAccount[](0);
        }
        uint256 remaining = owners.length - _offset;
        uint256 count = remaining < _limit ? remaining : _limit;

        LegacyAccount[] memory result = new LegacyAccount[](count);

        for (uint256 i = 0; i < count; ++i) {
            result[i] = _legacies[owners[_offset + i]][_beneficiary];
        }

        return result;
    }

    /**
     * @notice Returns legacies configured by a specific owner with pagination support.
     * @param _owner The address of the creator to query.
     * @param _offset The starting index for pagination (0-based).
     * @param _limit The maximum number of records to return (use 50 as default).
     * @return List of LegacyAccount structures (paginated).
     */
    function getHeirloomsByOwner(
        address _owner,
        uint256 _offset,
        uint256 _limit
    ) external view returns (LegacyAccount[] memory) {
        address[] memory beneficiaries = ownerBeneficiaries[_owner];
        if (beneficiaries.length == 0 || _offset > beneficiaries.length - 1 || _limit == 0) {
            return new LegacyAccount[](0);
        }
        uint256 remaining = beneficiaries.length - _offset;
        uint256 count = remaining < _limit ? remaining : _limit;

        LegacyAccount[] memory result = new LegacyAccount[](count);

        for (uint256 i = 0; i < count; ++i) {
            result[i] = _legacies[_owner][beneficiaries[_offset + i]];
        }

        return result;
    }
}
