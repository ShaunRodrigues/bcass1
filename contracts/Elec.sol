// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Elec {
    address public electionCommission;

    constructor() {
        electionCommission = msg.sender;
    }

    struct Candidate {
        uint id;
        string name;
        uint totalPoints;
    }

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint age;
    }

    mapping(uint => Candidate) public candidates;
    mapping(address => Voter) public voters;

    uint public candidatesCount = 0;

    // EVENTS
    event CandidateRegistered(uint id, string name);
    event VoterRegistered(address voter, uint age);
    event PointsCasted(address voter, uint candidateId, uint points);

    // Register a new candidate (only EC)
    function registerCandidate(string memory _name) public {
        require(msg.sender == electionCommission, "Only EC can register candidates");
        candidatesCount++;
        candidates[candidatesCount] = Candidate(candidatesCount, _name, 0);
        emit CandidateRegistered(candidatesCount, _name);
    }

    // Register a voter with age (only EC)
    function registerVoter(address _voter, uint _age) public {
        require(!voters[_voter].isRegistered, "Voter already registered");
        require(_age >= 18, "Voter must be at least 18 years old");

        voters[_voter] = Voter(true, false, _age);
        emit VoterRegistered(_voter, _age);
    }

    // Cast points to a candidate (1–5 points allowed)
    function vote(uint _candidateId, uint _points) public {
        Voter storage sender = voters[msg.sender];
        require(sender.isRegistered, "You are not registered to vote");
        require(sender.age >= 18, "You must be 18 or older to vote");
        require(!sender.hasVoted, "You have already voted");
        require(_candidateId > 0 && _candidateId <= candidatesCount, "Invalid candidate");
        require(_points >= 1 && _points <= 5, "Points must be between 1 and 5");

        candidates[_candidateId].totalPoints += _points;
        sender.hasVoted = true;
        emit PointsCasted(msg.sender, _candidateId, _points);
    }

    // View candidate details
    function getCandidate(uint _id) public view returns (string memory, uint) {
        Candidate memory c = candidates[_id];
        return (c.name, c.totalPoints);
    }
}