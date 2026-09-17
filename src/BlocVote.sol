// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IBlocVote} from './interface/IBlocVote.sol';

contract BlocVote is IBlocVote {
    address public immutable deployer = msg.sender;
    address public chairman;
    address public pendingChairman;

    Vote[] public votes;
    Candidate[] public candidates;
    Office[] public offices;

    // voterId => officeId => already voted for that office
    mapping(uint => mapping(uint => bool)) public hasVoted;

    modifier OnlyChairman() {
        require(msg.sender == chairman, "unauthorized");
        _;
    }

    constructor(address _chairman) {
        require(_chairman != address(0), "invalid chairman");
        chairman = _chairman;
        emit ChairmanChanged(address(0), _chairman);
    }

    // administration

    function proposeChairman(address _newChairman) external OnlyChairman {
        require(_newChairman != address(0), "invalid chairman");
        pendingChairman = _newChairman;

        emit ChairmanProposed(chairman, _newChairman);
    }

    function claimChairmanRole() external {
        require(msg.sender == pendingChairman, "unauthorized");

        address previousChairman = chairman;
        chairman = pendingChairman;
        pendingChairman = address(0);

        emit ChairmanChanged(previousChairman, chairman);
    }

    // candidate operation

    function registerCandidate(string calldata _name, uint _officeId) external OnlyChairman {
        require(_officeId < offices.length, "invalid office id");
        require(offices[_officeId].isValid, "Office invalid");

        uint index = candidates.length;
        Candidate memory candidate = Candidate({
            name: _name,
            officeId: _officeId,
            votes: 0,
            id: index,
            isValid: true
        });

        offices[_officeId].candidatesCount++;
        candidates.push(candidate);
        emit CandidateRegistered(index, _officeId, _name);
    }

    function removeCandidate(uint _candidateId) external OnlyChairman {
        require(_candidateId < candidates.length, "invalid candidate id");
        candidates[_candidateId].isValid = false;
        emit CandidateStatusChanged(_candidateId, false);
    }

    function reactivateCandidate(uint _candidateId) external OnlyChairman {
        require(_candidateId < candidates.length, "invalid candidate id");
        candidates[_candidateId].isValid = true;
        emit CandidateStatusChanged(_candidateId, true);
    }

    // office operation

    function registerOffice(string calldata _name) external OnlyChairman {
        uint index = offices.length;
        Office memory office = Office({
            id: index,
            name: _name,
            isValid: true,
            candidatesCount: 0
        });

        offices.push(office);
        emit OfficeRegistered(index, _name);
    }

    function removeOffice(uint _officeId) external OnlyChairman {
        require(_officeId < offices.length, "invalid office id");
        offices[_officeId].isValid = false;
        emit OfficeStatusChanged(_officeId, false);
    }

    function reactivateOffice(uint _officeId) external OnlyChairman {
        require(_officeId < offices.length, "invalid office id");
        offices[_officeId].isValid = true;
        emit OfficeStatusChanged(_officeId, true);
    }

    // voting process

    function castVote(Vote[] memory _votes) external OnlyChairman {
        for (uint _index; _index < _votes.length; _index++) {
            Vote memory _vote = _votes[_index];

            require(_vote.candidateId < candidates.length, "invalid candidate id");
            require(_vote.officeId < offices.length, "invalid office id");
            require(candidates[_vote.candidateId].isValid, "Candidate invalid");
            require(offices[_vote.officeId].isValid, "Office invalid");
            require(
                candidates[_vote.candidateId].officeId == _vote.officeId,
                "candidate does not contest this office"
            );
            require(!hasVoted[_vote.voterId][_vote.officeId], "already voted");

            hasVoted[_vote.voterId][_vote.officeId] = true;
            candidates[_vote.candidateId].votes++;
            votes.push(_vote);
            emit VoteCasted(_vote.voterId, _vote.officeId, _vote.candidateId);
        }
    }

    function candidateResult(uint _candidateId) external view returns (uint) {
        require(_candidateId < candidates.length, "invalid candidate id");

        uint _votes = candidates[_candidateId].votes;
        return _votes;
    }

    function getResult() external view returns (Result[] memory) {
        uint validCount;
        for (uint _index; _index < candidates.length; _index++) {
            if (candidates[_index].isValid) {
                validCount++;
            }
        }

        Result[] memory results = new Result[](validCount);

        uint _cursor;
        for (uint _index; _index < candidates.length; _index++) {
            if (candidates[_index].isValid) {
                results[_cursor] = Result({
                    candidateId: _index,
                    officeId: candidates[_index].officeId,
                    votes: candidates[_index].votes
                });
                _cursor++;
            }
        }
        return results;
    }
}
