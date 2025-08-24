// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./Ownable.sol";

import "./Elections/FPTPElection.sol";
import "./Elections/IRVElection.sol";
import "./Elections/CondorcetElection.sol";
import "./Elections/BordaElection.sol";
import "./Elections/PRElectionDhondt.sol";

contract ElectionFactory is Ownable {
    using Clones for address;

    VoterRegistry public registry;
    //uint256 public nextElectionId = 1;
    mapping(bytes32 => address) public elections;

    address public fptpImpl;
    address public irvImpl;
    address public condorcetImpl;
    address public bordaImpl;
    address public prImpl;

    event FPTPCreated(address indexed election, bytes32 id);
    event IRVCreated(address indexed election, bytes32 id);
    event CondorcetCreated(address indexed election, bytes32 id);
    event BordaCreated(address indexed election, bytes32 id);
    event PRCreated(address indexed election, bytes32 id);

    constructor(
        address _fptpImpl,
        address _irvImpl,
        address _condorcetImpl,
        address _bordaImpl,
        address _prImpl
    ) {
        fptpImpl = _fptpImpl;
        irvImpl = _irvImpl;
        condorcetImpl = _condorcetImpl;
        bordaImpl = _bordaImpl;
        prImpl = _prImpl;
    }

    function setImplementations(
        address _fptpImpl,
        address _irvImpl,
        address _condorcetImpl,
        address _bordaImpl,
        address _prImpl
    ) external onlyOwner {
        fptpImpl = _fptpImpl;
        irvImpl = _irvImpl;
        condorcetImpl = _condorcetImpl;
        bordaImpl = _bordaImpl;
        prImpl = _prImpl;
    }

    function _generateElectionId(address clone) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                clone,
                block.prevrandao // randomness in PoS Ethereum
            )
        );
    }

    function createFPTP(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = fptpImpl.clone();
        bytes32 electionId = _generateElectionId(clone);
        elections[electionId] = clone;
        // call initialize on clone
        FPTPElection(clone).initialize(registry, name, uint256(electionId), commitDeadline, revealDeadline, candidates, msg.sender);
        emit FPTPCreated(clone, electionId);
        return clone;
    }

    function createIRV(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = irvImpl.clone();
        bytes32 electionId = _generateElectionId(clone);
        elections[electionId] = clone;
        IRVElection(clone).initialize(registry, name, uint256(electionId), commitDeadline, revealDeadline, candidates, msg.sender);
        emit IRVCreated(clone, electionId);
        return clone;
    }

    function createCondorcet(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = condorcetImpl.clone();
        bytes32 electionId = _generateElectionId(clone);
        elections[electionId] = clone;
        CondorcetElection(clone).initialize(registry, name, uint256(electionId), commitDeadline, revealDeadline, candidates, msg.sender);
        emit CondorcetCreated(clone, electionId);
        return clone;
    }

    function createBorda(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = bordaImpl.clone();
        bytes32 electionId = _generateElectionId(clone);
        elections[electionId] = clone;
        BordaElection(clone).initialize(registry, name, uint256(electionId), commitDeadline, revealDeadline, candidates, msg.sender);
        emit BordaCreated(clone, electionId);
        return clone;
    }

    function createPRDhondt(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata partyNames,
        uint8 seats,
        uint16 thresholdBps
    ) external onlyOwner returns (address) {
        address clone = prImpl.clone();
        bytes32 electionId = _generateElectionId(clone);
        elections[electionId] = clone;
        PRElectionDhondt(clone).initialize(registry, name, uint256(electionId), commitDeadline, revealDeadline, partyNames, seats, thresholdBps, msg.sender);
        emit PRCreated(clone, electionId);
        return clone;
    }

}