// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IBlocVote} from './interface/IBlocVote.sol';

/// @title BlocVote
/// @notice On-chain election contract that stores candidates, offices, and votes.
/// @dev The chairman is the trusted election authority (e.g. INEC). Votes are
///      submitted in batches by the chairman on behalf of voters authenticated
///      off-chain. The contract enforces that each (voterId, officeId) pair
///      can only be recorded once, permanently preventing double-voting.
///
///      Chairman handover uses a two-step propose-and-claim pattern to prevent
///      accidental loss of control to an invalid or wrong address. A dedicated
///      cancel function lets the chairman safely retract an outstanding proposal.
contract BlocVote is IBlocVote {
    // ─── State ───────────────────────────────────────────────────────────────────

    /// @notice The account that deployed this contract (set once at construction).
    /// @dev When deployed via ContractFactory this equals the factory address,
    ///      not the human operator. See `chairman` for the controlling authority.
    address public immutable deployer = msg.sender;

    /// @notice The current election authority. Only this address may call
    ///         admin functions.
    address public chairman;

    /// @notice The address nominated to become the next chairman. Zero when
    ///         no handover is in progress.
    address public pendingChairman;

    /// @notice Append-only archive of every vote recorded on-chain.
    /// @dev Grows without bound; iterate via `votesCount()` + index access.
    ///      Only the chairman can add entries (OnlyChairman on castVote), so
    ///      there is no external DoS vector on this array.
    Vote[] public votes;

    /// @notice Array of all candidates, indexed by their ID.
    Candidate[] public candidates;

    /// @notice Array of all offices, indexed by their ID.
    Office[] public offices;

    /// @notice Double-vote guard: voterId => officeId => already voted.
    mapping(uint256 => mapping(uint256 => bool)) public hasVoted;

    // ─── Modifiers ───────────────────────────────────────────────────────────────

    modifier OnlyChairman() {
        require(msg.sender == chairman, "unauthorized");
        _;
    }

    // ─── Construction ────────────────────────────────────────────────────────────

    /// @param _chairman Address of the initial election authority. Must not be zero.
    constructor(address _chairman) {
        require(_chairman != address(0), "invalid chairman");
        chairman = _chairman;
        emit ChairmanChanged(address(0), _chairman);
    }

    // ─── Administration ──────────────────────────────────────────────────────────

    /// @inheritdoc IBlocVote
    function proposeChairman(address _newChairman) external OnlyChairman {
        require(_newChairman != address(0), "invalid chairman");
        // Prevent the chairman from silently resetting pendingChairman via a
        // self-proposal followed by claimChairmanRole(). Use
        // cancelChairmanProposal() to explicitly retract an outstanding proposal.
        require(_newChairman != chairman, "already chairman");

        pendingChairman = _newChairman;
        emit ChairmanProposed(chairman, _newChairman);
    }

    /// @inheritdoc IBlocVote
    function cancelChairmanProposal() external OnlyChairman {
        require(pendingChairman != address(0), "no pending proposal");

        address cancelled = pendingChairman;
        pendingChairman = address(0);
        emit ChairmanProposalCancelled(chairman, cancelled);
    }

    /// @inheritdoc IBlocVote
    function claimChairmanRole() external {
        require(msg.sender == pendingChairman, "unauthorized");

        address previous = chairman;
        chairman = pendingChairman;
        pendingChairman = address(0);

        // NOTE: forge linter incorrectly warns "missing-events-access-control"
        // for the two assignments above. ChairmanChanged IS emitted immediately
        // after — this is a confirmed false positive in the Forge linter.
        emit ChairmanChanged(previous, chairman);
    }

    // ─── Candidate Management ────────────────────────────────────────────────────

    /// @inheritdoc IBlocVote
    function registerCandidate(string calldata _name, uint256 _officeId) external OnlyChairman {
        require(bytes(_name).length > 0, "name required");
        require(_officeId < offices.length, "invalid office id");
        require(offices[_officeId].isValid, "Office invalid");

        uint256 id = candidates.length;
        candidates.push(Candidate({
            id: id,
            name: _name,
            officeId: _officeId,
            votes: 0,
            isValid: true
        }));

        offices[_officeId].candidatesCount++;
        emit CandidateRegistered(id, _officeId, _name);
    }

    /// @inheritdoc IBlocVote
    function removeCandidate(uint256 _candidateId) external OnlyChairman {
        require(_candidateId < candidates.length, "invalid candidate id");
        // Guard against duplicate events that would corrupt off-chain audit trails.
        require(candidates[_candidateId].isValid, "already removed");

        candidates[_candidateId].isValid = false;
        emit CandidateStatusChanged(_candidateId, false);
    }

    /// @inheritdoc IBlocVote
    function reactivateCandidate(uint256 _candidateId) external OnlyChairman {
        require(_candidateId < candidates.length, "invalid candidate id");
        // Guard against duplicate events that would corrupt off-chain audit trails.
        require(!candidates[_candidateId].isValid, "already active");

        candidates[_candidateId].isValid = true;
        emit CandidateStatusChanged(_candidateId, true);
    }

    // ─── Office Management ───────────────────────────────────────────────────────

    /// @inheritdoc IBlocVote
    function registerOffice(string calldata _name) external OnlyChairman {
        require(bytes(_name).length > 0, "name required");

        uint256 id = offices.length;
        offices.push(Office({
            id: id,
            name: _name,
            isValid: true,
            candidatesCount: 0
        }));

        emit OfficeRegistered(id, _name);
    }

    /// @inheritdoc IBlocVote
    function removeOffice(uint256 _officeId) external OnlyChairman {
        require(_officeId < offices.length, "invalid office id");
        // Guard against duplicate events that would corrupt off-chain audit trails.
        require(offices[_officeId].isValid, "already removed");

        offices[_officeId].isValid = false;
        emit OfficeStatusChanged(_officeId, false);
    }

    /// @inheritdoc IBlocVote
    function reactivateOffice(uint256 _officeId) external OnlyChairman {
        require(_officeId < offices.length, "invalid office id");
        // Guard against duplicate events that would corrupt off-chain audit trails.
        require(!offices[_officeId].isValid, "already active");

        offices[_officeId].isValid = true;
        emit OfficeStatusChanged(_officeId, true);
    }

    // ─── Vote Processing ─────────────────────────────────────────────────────────

    /// @inheritdoc IBlocVote
    /// @dev The require-in-loop pattern is intentional: each vote in a batch must
    ///      be fully valid or the entire transaction reverts atomically. This is
    ///      deliberate by design — no partial batches are accepted.
    ///      Forge linter warning "require-revert-in-loop" is a known false positive
    ///      for this pattern.
    function castVote(Vote[] memory _votes) external OnlyChairman {
        require(_votes.length > 0, "empty ballot");

        for (uint256 i; i < _votes.length; i++) {
            Vote memory v = _votes[i];

            require(v.candidateId < candidates.length, "invalid candidate id");
            require(v.officeId < offices.length, "invalid office id");
            require(candidates[v.candidateId].isValid, "Candidate invalid");
            require(offices[v.officeId].isValid, "Office invalid");
            require(
                candidates[v.candidateId].officeId == v.officeId,
                "candidate does not contest this office"
            );
            require(!hasVoted[v.voterId][v.officeId], "already voted");

            hasVoted[v.voterId][v.officeId] = true;
            candidates[v.candidateId].votes++;
            votes.push(v);

            emit VoteCasted(v.voterId, v.officeId, v.candidateId);
        }
    }

    // ─── Query ───────────────────────────────────────────────────────────────────

    /// @inheritdoc IBlocVote
    function candidateResult(uint256 _candidateId) external view returns (uint256) {
        require(_candidateId < candidates.length, "invalid candidate id");
        return candidates[_candidateId].votes;
    }

    /// @inheritdoc IBlocVote
    /// @dev Two-pass O(2n) algorithm: first count valid candidates to size the
    ///      memory array, then populate it. Gas-free as a view function.
    ///      Forge linter "uninitialized-local" warnings on `validCount` and
    ///      `cursor` are false positives — Solidity guarantees uint256 = 0.
    function getResult() external view returns (Result[] memory) {
        uint256 validCount;
        for (uint256 i; i < candidates.length; i++) {
            if (candidates[i].isValid) validCount++;
        }

        Result[] memory results = new Result[](validCount);
        uint256 cursor;

        for (uint256 i; i < candidates.length; i++) {
            Candidate storage c = candidates[i];
            if (c.isValid) {
                results[cursor] = Result({
                    candidateId: i,
                    candidateName: c.name,
                    officeId: c.officeId,
                    votes: c.votes
                });
                cursor++;
            }
        }

        return results;
    }

    /// @inheritdoc IBlocVote
    function candidatesCount() external view returns (uint256) {
        return candidates.length;
    }

    /// @inheritdoc IBlocVote
    function officesCount() external view returns (uint256) {
        return offices.length;
    }

    /// @inheritdoc IBlocVote
    function votesCount() external view returns (uint256) {
        return votes.length;
    }
}
