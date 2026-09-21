// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title IBlocVote
/// @notice Interface for the BlocVote on-chain election contract.
/// @dev The chairman is the trusted election authority who manages the election
///      lifecycle. Votes are submitted in batches by the chairman on behalf of
///      voters identified by an off-chain `voterId` (e.g. a hashed NIN or voter
///      registration number). The contract guarantees that each (voterId, officeId)
///      pair can only be recorded once, preventing double-voting even across batches.
interface IBlocVote {
    // ─── Data Structures ────────────────────────────────────────────────────────

    /// @notice Represents a candidate contesting a specific office.
    struct Candidate {
        uint256 id;
        string name;
        uint256 officeId;
        bool isValid;
        uint256 votes;
    }

    /// @notice Represents an elective office (e.g. "President", "Senator").
    struct Office {
        uint256 id;
        string name;
        bool isValid;
        /// @dev Total number of candidates ever registered for this office.
        ///      Does not decrease on candidate removal; use `isValid` on each
        ///      candidate to determine currently active contestants.
        uint256 candidatesCount;
    }

    /// @notice Represents a single vote in a ballot submission.
    struct Vote {
        uint256 candidateId;
        uint256 officeId;
        /// @dev Off-chain voter identifier (e.g. hashed NIN). The contract
        ///      tracks (voterId => officeId) uniqueness, not msg.sender.
        uint256 voterId;
    }

    /// @notice Summary result entry returned by `getResult()`.
    struct Result {
        uint256 candidateId;
        string candidateName;
        uint256 officeId;
        uint256 votes;
    }

    // ─── Events ─────────────────────────────────────────────────────────────────

    /// @notice Emitted when the current chairman proposes a successor.
    event ChairmanProposed(address indexed chairman, address indexed pendingChairman);

    /// @notice Emitted when the current chairman cancels an outstanding proposal.
    event ChairmanProposalCancelled(address indexed chairman, address indexed cancelledProposal);

    /// @notice Emitted when a pending chairman successfully claims the role.
    event ChairmanChanged(address indexed previousChairman, address indexed newChairman);

    /// @notice Emitted when a new elective office is registered.
    event OfficeRegistered(uint256 indexed officeId, string name);

    /// @notice Emitted when an office's active status changes.
    event OfficeStatusChanged(uint256 indexed officeId, bool isValid);

    /// @notice Emitted when a new candidate is registered for an office.
    event CandidateRegistered(uint256 indexed candidateId, uint256 indexed officeId, string name);

    /// @notice Emitted when a candidate's active status changes.
    event CandidateStatusChanged(uint256 indexed candidateId, bool isValid);

    /// @notice Emitted for each individual vote recorded on-chain.
    event VoteCasted(uint256 indexed voterId, uint256 indexed officeId, uint256 indexed candidateId);

    // ─── Administration ──────────────────────────────────────────────────────────

    /// @notice Step 1 of 2 for chairman handover: propose a successor address.
    /// @dev Only callable by the current chairman. Does NOT transfer the role
    ///      immediately; the nominee must call `claimChairmanRole` to accept.
    ///      Cannot propose the current chairman's own address — use
    ///      `cancelChairmanProposal` to retract an outstanding proposal instead.
    /// @param _newChairman Address of the proposed chairman. Must not be zero
    ///        and must not be the current chairman.
    function proposeChairman(address _newChairman) external;

    /// @notice Cancel an outstanding chairman proposal before it is claimed.
    /// @dev Only callable by the current chairman. Reverts if there is no
    ///      pending proposal.
    function cancelChairmanProposal() external;

    /// @notice Step 2 of 2 for chairman handover: the pending chairman accepts.
    /// @dev Only callable by the address stored in `pendingChairman`. Clears
    ///      `pendingChairman` after a successful transfer.
    function claimChairmanRole() external;

    // ─── Candidate Management ────────────────────────────────────────────────────

    /// @notice Register a new candidate for an existing, active office.
    /// @param _name      Non-empty display name of the candidate.
    /// @param _officeId  ID of an existing and currently active office.
    function registerCandidate(string calldata _name, uint256 _officeId) external;

    /// @notice Deactivate a candidate, preventing new votes from being cast for them.
    /// @dev Reverts if the candidate is already inactive.
    /// @param _candidateId  ID of an existing, currently active candidate.
    function removeCandidate(uint256 _candidateId) external;

    /// @notice Re-activate a previously deactivated candidate.
    /// @dev Reverts if the candidate is already active.
    /// @param _candidateId  ID of an existing, currently inactive candidate.
    function reactivateCandidate(uint256 _candidateId) external;

    // ─── Office Management ───────────────────────────────────────────────────────

    /// @notice Register a new elective office.
    /// @param _name  Non-empty display name of the office.
    function registerOffice(string calldata _name) external;

    /// @notice Deactivate an office, preventing new votes from being cast for it.
    /// @dev Reverts if the office is already inactive.
    /// @param _officeId  ID of an existing, currently active office.
    function removeOffice(uint256 _officeId) external;

    /// @notice Re-activate a previously deactivated office.
    /// @dev Reverts if the office is already active.
    /// @param _officeId  ID of an existing, currently inactive office.
    function reactivateOffice(uint256 _officeId) external;

    // ─── Vote Processing ─────────────────────────────────────────────────────────

    /// @notice Submit a batch of votes. Each entry is validated atomically —
    ///         if any single vote is invalid the entire transaction reverts,
    ///         leaving the contract state unchanged.
    /// @dev Restricted to the chairman to ensure votes come from a verified,
    ///      off-chain-authenticated source. Each (voterId, officeId) pair may
    ///      only appear once across all calls — including within a single batch.
    /// @param _votes  Non-empty array of Vote structs to record.
    function castVote(Vote[] memory _votes) external;

    // ─── Query ───────────────────────────────────────────────────────────────────

    /// @notice Returns the vote count for a single candidate.
    /// @param _candidateId  ID of an existing candidate (active or inactive).
    function candidateResult(uint256 _candidateId) external view returns (uint256);

    /// @notice Returns a result summary for every currently active candidate.
    function getResult() external view returns (Result[] memory);

    /// @notice Total number of candidates ever registered (including removed ones).
    function candidatesCount() external view returns (uint256);

    /// @notice Total number of offices ever registered (including removed ones).
    function officesCount() external view returns (uint256);

    /// @notice Total number of individual votes recorded in the archive.
    function votesCount() external view returns (uint256);
}
