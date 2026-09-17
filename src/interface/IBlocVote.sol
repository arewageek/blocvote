// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IBlocVote {
    struct Candidate {
        uint id;
        string name;
        uint officeId;
        bool isValid;
        uint votes;
    }

    struct Office {
        uint id;
        string name;
        bool isValid;
        uint candidatesCount;
    }

    struct Vote {
        uint candidateId;
        uint officeId;
        uint voterId;
    }

    struct Result {
        uint candidateId;
        uint officeId;
        uint votes;
    }

    event ChairmanProposed(address indexed chairman, address indexed pendingChairman);
    event ChairmanChanged(address indexed previousChairman, address indexed newChairman);

    event OfficeRegistered(uint indexed officeId, string name);
    event OfficeStatusChanged(uint indexed officeId, bool isValid);
    
    event CandidateRegistered(uint indexed candidateId, uint indexed officeId, string name);
    event CandidateStatusChanged(uint indexed candidateId, bool isValid);
    
    event VoteCasted(uint indexed voterId, uint indexed officeId, uint indexed candidateId);

    // administration
    function proposeChairman(address _newChairman) external;
    function claimChairmanRole() external;

    // candidate
    function registerCandidate(string calldata _name, uint _officeId) external;
    function removeCandidate(uint _candidateId) external;
    function reactivateCandidate(uint _candidateId) external;

    // office
    function registerOffice(string calldata _name) external;
    function removeOffice(uint _officeId) external;
    function reactivateOffice(uint _officeId) external;

    // vote processing
    function castVote(Vote[] memory _votes) external;
    function getResult() external view returns (Result[] memory);
    function candidateResult(uint candidateId) external view returns (uint);
}
