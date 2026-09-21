// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BlocVote} from "../src/BlocVote.sol";
import {IBlocVote} from "../src/interface/IBlocVote.sol";

contract BlocVoteTest is Test {
    BlocVote public blocVote;

    address chairman = address(0xC4A1);
    address newChairman = address(0xC4A2);
    address attacker = address(0xBAD);

    uint constant PRESIDENT = 0;
    uint constant SENATOR = 1;

    function setUp() public {
        blocVote = new BlocVote(chairman);

        vm.startPrank(chairman);
        blocVote.registerOffice("President"); // office 0
        blocVote.registerOffice("Senator"); // office 1
        blocVote.registerCandidate("Alice", PRESIDENT); // candidate 0
        blocVote.registerCandidate("Bob", PRESIDENT); // candidate 1
        blocVote.registerCandidate("Carol", SENATOR); // candidate 2
        vm.stopPrank();
    }

    function _vote(uint candidateId, uint officeId, uint voterId)
        internal
        pure
        returns (IBlocVote.Vote[] memory ballot)
    {
        ballot = new IBlocVote.Vote[](1);
        ballot[0] = IBlocVote.Vote({candidateId: candidateId, officeId: officeId, voterId: voterId});
    }

    // --- 1. Two-step chairman assignment ---

    function test_ConstructorSetsChairman() public view {
        assertEq(blocVote.chairman(), chairman);
        assertEq(blocVote.pendingChairman(), address(0));
    }

    function test_ConstructorRejectsZeroChairman() public {
        vm.expectRevert("invalid chairman");
        new BlocVote(address(0));
    }

    function test_ProposeDoesNotTransferRoleImmediately() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);

        assertEq(blocVote.chairman(), chairman, "chairman must not change on propose");
        assertEq(blocVote.pendingChairman(), newChairman);
    }

    function test_ClaimCompletesTransfer() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);

        vm.prank(newChairman);
        blocVote.claimChairmanRole();

        assertEq(blocVote.chairman(), newChairman);
        assertEq(blocVote.pendingChairman(), address(0), "pending must be cleared");
    }

    function test_OnlyChairmanCanPropose() public {
        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.proposeChairman(attacker);
    }

    function test_ProposeRejectsZeroAddress() public {
        vm.prank(chairman);
        vm.expectRevert("invalid chairman");
        blocVote.proposeChairman(address(0));
    }

    function test_OnlyPendingChairmanCanClaim() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);

        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.claimChairmanRole();

        // old chairman cannot claim on the pending chairman's behalf either
        vm.prank(chairman);
        vm.expectRevert("unauthorized");
        blocVote.claimChairmanRole();
    }

    function test_ClaimCannotBeReplayed() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);

        vm.startPrank(newChairman);
        blocVote.claimChairmanRole();
        vm.expectRevert("unauthorized");
        blocVote.claimChairmanRole();
        vm.stopPrank();
    }

    function test_OldChairmanLosesPowerAfterHandover() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);
        vm.prank(newChairman);
        blocVote.claimChairmanRole();

        vm.prank(chairman);
        vm.expectRevert("unauthorized");
        blocVote.registerOffice("Governor");

        vm.prank(newChairman);
        blocVote.registerOffice("Governor");
        (,, bool isValid,) = blocVote.offices(2);
        assertTrue(isValid);
    }

    // --- 2A. Access control on every admin function ---

    function test_AttackerCannotRegisterOffice() public {
        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.registerOffice("Fake Office");
    }

    function test_AttackerCannotRegisterCandidate() public {
        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.registerCandidate("Mallory", PRESIDENT);
    }

    function test_AttackerCannotRemoveCandidate() public {
        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.removeCandidate(0);
    }

    function test_AttackerCannotReactivateCandidate() public {
        vm.prank(chairman);
        blocVote.removeCandidate(0);

        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.reactivateCandidate(0);
    }

    function test_AttackerCannotRemoveOrReactivateOffice() public {
        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.removeOffice(PRESIDENT);

        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.reactivateOffice(PRESIDENT);
    }

    // --- 2B. Double voting / voter identification ---

    function test_VoteIsRecordedWithVoterId() public {
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 777));

        (uint candidateId, uint officeId, uint voterId) = blocVote.votes(0);
        assertEq(candidateId, 0);
        assertEq(officeId, PRESIDENT);
        assertEq(voterId, 777);
        assertTrue(blocVote.hasVoted(777, PRESIDENT));
    }

    function test_DoubleVotingReverts() public {
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 777));

        vm.expectRevert("already voted");
        vm.prank(chairman);
        blocVote.castVote(_vote(1, PRESIDENT, 777));

        assertEq(blocVote.candidateResult(0), 1);
        assertEq(blocVote.candidateResult(1), 0, "second ballot must not count");
    }

    function test_DoubleVotingWithinSameBatchReverts() public {
        IBlocVote.Vote[] memory ballot = new IBlocVote.Vote[](2);
        ballot[0] = IBlocVote.Vote({candidateId: 0, officeId: PRESIDENT, voterId: 777});
        ballot[1] = IBlocVote.Vote({candidateId: 1, officeId: PRESIDENT, voterId: 777});

        vm.expectRevert("already voted");
        vm.prank(chairman);
        blocVote.castVote(ballot);

        assertEq(blocVote.candidateResult(0), 0, "whole batch must revert");
    }

    function test_SameVoterMayVoteOncePerOffice() public {
        IBlocVote.Vote[] memory ballot = new IBlocVote.Vote[](2);
        ballot[0] = IBlocVote.Vote({candidateId: 0, officeId: PRESIDENT, voterId: 777});
        ballot[1] = IBlocVote.Vote({candidateId: 2, officeId: SENATOR, voterId: 777});

        vm.prank(chairman);
        blocVote.castVote(ballot);

        assertEq(blocVote.candidateResult(0), 1);
        assertEq(blocVote.candidateResult(2), 1);
    }

    function test_DistinctVotersBothCount() public {
        vm.startPrank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
        blocVote.castVote(_vote(0, PRESIDENT, 2));
        vm.stopPrank();

        assertEq(blocVote.candidateResult(0), 2);
    }

    // --- 2C. Votes are tallied ---

    function test_TallyIncrementsCandidateVotes() public {
        vm.startPrank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
        blocVote.castVote(_vote(0, PRESIDENT, 2));
        blocVote.castVote(_vote(1, PRESIDENT, 3));
        vm.stopPrank();

        assertEq(blocVote.candidateResult(0), 2, "Alice");
        assertEq(blocVote.candidateResult(1), 1, "Bob");

        (,,,, uint storedVotes) = blocVote.candidates(0);
        assertEq(storedVotes, 2);
    }

    function test_GetResultReflectsTally() public {
        vm.startPrank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
        blocVote.castVote(_vote(2, SENATOR, 1));
        vm.stopPrank();

        IBlocVote.Result[] memory results = blocVote.getResult();
        assertEq(results.length, 3);

        assertEq(results[0].candidateId, 0);
        assertEq(results[0].officeId, PRESIDENT);
        assertEq(results[0].votes, 1);

        assertEq(results[2].candidateId, 2);
        assertEq(results[2].officeId, SENATOR);
        assertEq(results[2].votes, 1);
    }

    function test_GetResultSkipsRemovedCandidates() public {
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));

        vm.prank(chairman);
        blocVote.removeCandidate(1);

        IBlocVote.Result[] memory results = blocVote.getResult();
        assertEq(results.length, 2, "removed candidate must not occupy a slot");

        for (uint i; i < results.length; i++) {
            assertTrue(results[i].candidateId != 1, "removed candidate leaked into results");
        }
    }

    // --- 2E. Candidate count per office ---

    function test_OfficeCandidateCountIncrements() public {
        (,,, uint presidentCount) = blocVote.offices(PRESIDENT);
        (,,, uint senatorCount) = blocVote.offices(SENATOR);

        assertEq(presidentCount, 2, "President has Alice and Bob");
        assertEq(senatorCount, 1, "Senator has Carol");

        vm.prank(chairman);
        blocVote.registerCandidate("Dave", SENATOR);

        (,,, senatorCount) = blocVote.offices(SENATOR);
        assertEq(senatorCount, 2);
    }

    // --- 2F. Validation and bounds checks ---

    function test_CannotVoteForRemovedCandidate() public {
        vm.prank(chairman);
        blocVote.removeCandidate(0);

        vm.expectRevert("Candidate invalid");
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
    }

    function test_CannotVoteInRemovedOffice() public {
        vm.prank(chairman);
        blocVote.removeOffice(PRESIDENT);

        vm.expectRevert("Office invalid");
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
    }

    function test_CannotVoteForNonExistentCandidateOrOffice() public {
        vm.expectRevert("invalid candidate id");
        vm.prank(chairman);
        blocVote.castVote(_vote(99, PRESIDENT, 1));

        vm.expectRevert("invalid office id");
        vm.prank(chairman);
        blocVote.castVote(_vote(0, 99, 1));
    }

    function test_CannotVoteForCandidateOfAnotherOffice() public {
        vm.expectRevert("candidate does not contest this office");
        vm.prank(chairman);
        blocVote.castVote(_vote(2, PRESIDENT, 1)); // Carol runs for Senator
    }

    function test_FailedVoteDoesNotBurnVoterEligibility() public {
        vm.expectRevert("invalid candidate id");
        vm.prank(chairman);
        blocVote.castVote(_vote(99, PRESIDENT, 1));

        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
        assertEq(blocVote.candidateResult(0), 1);
    }

    function test_AdminBoundsChecksGiveClearErrors() public {
        vm.startPrank(chairman);

        vm.expectRevert("invalid candidate id");
        blocVote.removeCandidate(99);

        vm.expectRevert("invalid candidate id");
        blocVote.reactivateCandidate(99);

        vm.expectRevert("invalid office id");
        blocVote.removeOffice(99);

        vm.expectRevert("invalid office id");
        blocVote.reactivateOffice(99);

        vm.expectRevert("invalid office id");
        blocVote.registerCandidate("Nobody", 99);

        vm.stopPrank();

        vm.expectRevert("invalid candidate id");
        blocVote.candidateResult(99);
    }

    function test_CannotRegisterCandidateForRemovedOffice() public {
        vm.startPrank(chairman);
        blocVote.removeOffice(SENATOR);

        vm.expectRevert("Office invalid");
        blocVote.registerCandidate("Dave", SENATOR);
        vm.stopPrank();
    }

    // --- 2F-extra. Empty name validation ---

    function test_RegisterOfficeRejectsEmptyName() public {
        vm.prank(chairman);
        vm.expectRevert("name required");
        blocVote.registerOffice("");
    }

    function test_RegisterCandidateRejectsEmptyName() public {
        vm.prank(chairman);
        vm.expectRevert("name required");
        blocVote.registerCandidate("", PRESIDENT);
    }

    // --- 2G. Empty ballot guard ---

    function test_CastVoteRejectsEmptyBallot() public {
        IBlocVote.Vote[] memory emptyBallot = new IBlocVote.Vote[](0);
        vm.prank(chairman);
        vm.expectRevert("empty ballot");
        blocVote.castVote(emptyBallot);
    }

    // --- 2H. Result struct includes candidate name ---

    function test_GetResultIncludesCandidateName() public {
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));

        IBlocVote.Result[] memory results = blocVote.getResult();

        // Alice is candidate 0, Bob is candidate 1, Carol is candidate 2
        assertEq(results[0].candidateName, "Alice");
        assertEq(results[1].candidateName, "Bob");
        assertEq(results[2].candidateName, "Carol");
    }

    // ─── C-1: Chairman self-proposal attack ─────────────────────────────────────

    function test_ProposeChairmanRejectsSelf() public {
        // Without this guard the chairman could propose themselves, call
        // claimChairmanRole(), and silently wipe any pending handover.
        vm.prank(chairman);
        vm.expectRevert("already chairman");
        blocVote.proposeChairman(chairman);
    }

    function test_SecondProposeOverwritesFirstPending() public {
        address thirdChairman = address(0xC4A3);

        vm.startPrank(chairman);
        blocVote.proposeChairman(newChairman);
        blocVote.proposeChairman(thirdChairman); // overwrites
        vm.stopPrank();

        // newChairman was displaced — only thirdChairman can now claim.
        vm.prank(newChairman);
        vm.expectRevert("unauthorized");
        blocVote.claimChairmanRole();

        vm.prank(thirdChairman);
        blocVote.claimChairmanRole();
        assertEq(blocVote.chairman(), thirdChairman);
    }

    // ─── M-1: Chairman proposal cancellation ────────────────────────────────────

    function test_CancelChairmanProposal() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);
        assertEq(blocVote.pendingChairman(), newChairman);

        vm.prank(chairman);
        blocVote.cancelChairmanProposal();
        assertEq(blocVote.pendingChairman(), address(0), "pending must be cleared");

        vm.prank(newChairman);
        vm.expectRevert("unauthorized");
        blocVote.claimChairmanRole();
    }

    function test_CancelRevertsWhenNoPendingProposal() public {
        vm.prank(chairman);
        vm.expectRevert("no pending proposal");
        blocVote.cancelChairmanProposal();
    }

    function test_OnlyChairmanCanCancel() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);

        vm.prank(attacker);
        vm.expectRevert("unauthorized");
        blocVote.cancelChairmanProposal();

        // The pending chairman also cannot cancel — only the current chairman.
        vm.prank(newChairman);
        vm.expectRevert("unauthorized");
        blocVote.cancelChairmanProposal();
    }

    function test_CancelAfterClaimRevertsNoPending() public {
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);
        vm.prank(newChairman);
        blocVote.claimChairmanRole();

        // pendingChairman is address(0) after claim — no proposal to cancel.
        vm.prank(newChairman);
        vm.expectRevert("no pending proposal");
        blocVote.cancelChairmanProposal();
    }

    // ─── C-2: Idempotency guards on status toggles ───────────────────────────────

    function test_RemoveCandidateRevertsIfAlreadyRemoved() public {
        vm.startPrank(chairman);
        blocVote.removeCandidate(0);

        vm.expectRevert("already removed");
        blocVote.removeCandidate(0); // duplicate — must not emit phantom event
        vm.stopPrank();
    }

    function test_ReactivateCandidateRevertsIfAlreadyActive() public {
        // candidate 0 is active from setUp — reactivating must revert
        vm.prank(chairman);
        vm.expectRevert("already active");
        blocVote.reactivateCandidate(0);
    }

    function test_RemoveThenReactivateThenRemoveIsLegal() public {
        vm.startPrank(chairman);
        blocVote.removeCandidate(0);
        blocVote.reactivateCandidate(0);
        blocVote.removeCandidate(0);
        vm.stopPrank();

        (,,, bool isValid,) = blocVote.candidates(0);
        assertFalse(isValid);
    }

    function test_RemoveOfficeRevertsIfAlreadyRemoved() public {
        vm.startPrank(chairman);
        blocVote.removeOffice(PRESIDENT);

        vm.expectRevert("already removed");
        blocVote.removeOffice(PRESIDENT);
        vm.stopPrank();
    }

    function test_ReactivateOfficeRevertsIfAlreadyActive() public {
        // offices are active from setUp
        vm.prank(chairman);
        vm.expectRevert("already active");
        blocVote.reactivateOffice(PRESIDENT);
    }

    function test_RemoveThenReactivateOfficeCycleIsLegal() public {
        vm.startPrank(chairman);
        blocVote.removeOffice(SENATOR);
        blocVote.reactivateOffice(SENATOR);
        blocVote.removeOffice(SENATOR);
        vm.stopPrank();

        (,, bool isValid,) = blocVote.offices(SENATOR);
        assertFalse(isValid);
    }

    // ─── H-3: Count accessors ────────────────────────────────────────────────────

    function test_CountAccessorsReflectState() public {
        assertEq(blocVote.candidatesCount(), 3, "Alice + Bob + Carol");
        assertEq(blocVote.officesCount(), 2, "President + Senator");
        assertEq(blocVote.votesCount(), 0, "no votes cast yet");

        vm.startPrank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
        blocVote.castVote(_vote(2, SENATOR, 1));
        vm.stopPrank();

        assertEq(blocVote.votesCount(), 2);

        vm.prank(chairman);
        blocVote.registerCandidate("Dave", SENATOR);
        assertEq(blocVote.candidatesCount(), 4);

        // Removal is soft-delete: candidatesCount must not change.
        vm.prank(chairman);
        blocVote.removeCandidate(0);
        assertEq(blocVote.candidatesCount(), 4, "soft-delete must not alter count");
    }

    // ─── Batch atomicity edge cases ───────────────────────────────────────────────

    function test_BatchPartialFailureRevertsEntirely() public {
        IBlocVote.Vote[] memory ballot = new IBlocVote.Vote[](2);
        ballot[0] = IBlocVote.Vote({candidateId: 0, officeId: PRESIDENT, voterId: 10});
        ballot[1] = IBlocVote.Vote({candidateId: 99, officeId: PRESIDENT, voterId: 11}); // bad

        vm.prank(chairman);
        vm.expectRevert("invalid candidate id");
        blocVote.castVote(ballot);

        assertEq(blocVote.candidateResult(0), 0, "first entry must not persist");
        assertEq(blocVote.votesCount(), 0, "archive must be unchanged");
        assertFalse(blocVote.hasVoted(10, PRESIDENT), "voter eligibility must not be burned");
    }

    function test_MultiOfficeSingleBatchSucceeds() public {
        IBlocVote.Vote[] memory ballot = new IBlocVote.Vote[](2);
        ballot[0] = IBlocVote.Vote({candidateId: 0, officeId: PRESIDENT, voterId: 42});
        ballot[1] = IBlocVote.Vote({candidateId: 2, officeId: SENATOR,   voterId: 42});

        vm.prank(chairman);
        blocVote.castVote(ballot);

        assertEq(blocVote.candidateResult(0), 1);
        assertEq(blocVote.candidateResult(2), 1);
        assertEq(blocVote.votesCount(), 2);
    }

    // ─── Vote history persistence across deactivation ────────────────────────────

    function test_ReactivatedCandidateRetainsVoteHistory() public {
        vm.startPrank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));
        blocVote.castVote(_vote(0, PRESIDENT, 2));

        blocVote.removeCandidate(0);

        // No new votes while removed.
        vm.expectRevert("Candidate invalid");
        blocVote.castVote(_vote(0, PRESIDENT, 3));

        // Historical votes must survive reactivation.
        blocVote.reactivateCandidate(0);
        assertEq(blocVote.candidateResult(0), 2, "votes must persist across removal");

        // Can receive new votes after reactivation.
        blocVote.castVote(_vote(0, PRESIDENT, 3));
        assertEq(blocVote.candidateResult(0), 3);
        vm.stopPrank();
    }

    function test_ReactivatedOfficeResumesVoting() public {
        vm.startPrank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 1));

        blocVote.removeOffice(PRESIDENT);
        vm.expectRevert("Office invalid");
        blocVote.castVote(_vote(0, PRESIDENT, 2));

        blocVote.reactivateOffice(PRESIDENT);
        blocVote.castVote(_vote(0, PRESIDENT, 2)); // now permitted
        assertEq(blocVote.candidateResult(0), 2);
        vm.stopPrank();
    }

    // ─── Boundary values ─────────────────────────────────────────────────────────

    function test_MaxUint256VoterIdIsValid() public {
        uint256 maxId = type(uint256).max;
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, maxId));

        assertTrue(blocVote.hasVoted(maxId, PRESIDENT));
        assertEq(blocVote.candidateResult(0), 1);

        // Must prevent second vote at max ID.
        vm.prank(chairman);
        vm.expectRevert("already voted");
        blocVote.castVote(_vote(1, PRESIDENT, maxId));
    }

    function test_VoterIdZeroIsValid() public {
        vm.prank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 0));

        assertTrue(blocVote.hasVoted(0, PRESIDENT));

        vm.prank(chairman);
        vm.expectRevert("already voted");
        blocVote.castVote(_vote(1, PRESIDENT, 0));
    }

    // ─── Full election lifecycle integration ─────────────────────────────────────

    function test_FullElectionLifecycle() public {
        assertEq(blocVote.candidatesCount(), 3);
        assertEq(blocVote.officesCount(), 2);

        // Disqualify Bob.
        vm.prank(chairman);
        blocVote.removeCandidate(1);

        // Cast 5 votes across two offices.
        vm.startPrank(chairman);
        blocVote.castVote(_vote(0, PRESIDENT, 101));
        blocVote.castVote(_vote(0, PRESIDENT, 102));
        blocVote.castVote(_vote(0, PRESIDENT, 103));
        blocVote.castVote(_vote(2, SENATOR,   101));
        blocVote.castVote(_vote(2, SENATOR,   102));
        vm.stopPrank();

        assertEq(blocVote.votesCount(), 5);

        IBlocVote.Result[] memory results = blocVote.getResult();
        assertEq(results.length, 2, "Bob must be excluded");
        assertEq(results[0].candidateName, "Alice");
        assertEq(results[0].votes, 3);
        assertEq(results[1].candidateName, "Carol");
        assertEq(results[1].votes, 2);

        // Handover: new chairman can still operate.
        vm.prank(chairman);
        blocVote.proposeChairman(newChairman);
        vm.prank(newChairman);
        blocVote.claimChairmanRole();

        vm.prank(newChairman);
        blocVote.castVote(_vote(0, PRESIDENT, 104));
        assertEq(blocVote.candidateResult(0), 4, "new chairman vote must count");
    }

    // ─── fuzz ────────────────────────────────────────────────────────────────────

    function testFuzz_EachVoterCountsExactlyOncePerOffice(uint8 voterCount) public {
        vm.assume(voterCount > 0);

        for (uint i; i < voterCount; i++) {
            vm.prank(chairman);
            blocVote.castVote(_vote(0, PRESIDENT, i));
        }

        assertEq(blocVote.candidateResult(0), voterCount);

        for (uint i; i < voterCount; i++) {
            vm.expectRevert("already voted");
            vm.prank(chairman);
            blocVote.castVote(_vote(1, PRESIDENT, i));
        }

        assertEq(blocVote.candidateResult(1), 0);
    }

    function testFuzz_OnlyChairmanPassesAccessControl(address caller) public {
        vm.assume(caller != chairman);

        vm.prank(caller);
        vm.expectRevert("unauthorized");
        blocVote.registerOffice("Office");
    }

    function testFuzz_ProposeRejectsSelf(address randomChairman) public {
        vm.assume(randomChairman != address(0));

        BlocVote fresh = new BlocVote(randomChairman);

        vm.prank(randomChairman);
        vm.expectRevert("already chairman");
        fresh.proposeChairman(randomChairman);
    }
}
