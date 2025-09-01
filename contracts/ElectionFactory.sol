// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./Ownable.sol";

import "./Elections/FPTPElection.sol";
import "./Elections/IRVElection.sol";
import "./Elections/CondorcetElection.sol";
import "./Elections/BordaElection.sol";
//import "./Elections/PRElectionDhondt.sol";

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

    event FPTPCreated(address indexed election);
    event IRVCreated(address indexed election);
    event CondorcetCreated(address indexed election);
    event BordaCreated(address indexed election);
    event PRCreated(address indexed election);

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

    function createFPTP(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = fptpImpl.clone();
        // call initialize on clone
        FPTPElection(clone).initialize(registry, clone, name, commitDeadline, revealDeadline, candidates, msg.sender);
        emit FPTPCreated(clone);
        return clone;
    }

    function createIRV(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = irvImpl.clone();
        IRVElection(clone).initialize(registry, clone, name, commitDeadline, revealDeadline, candidates, msg.sender);
        emit IRVCreated(clone);
        return clone;
    }

    function createCondorcet(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = condorcetImpl.clone();
        CondorcetElection(clone).initialize(registry, clone, name, commitDeadline, revealDeadline, candidates, msg.sender);
        emit CondorcetCreated(clone);
        return clone;
    }

    function createBorda(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata candidates
    ) external onlyOwner returns (address) {
        address clone = bordaImpl.clone();
        BordaElection(clone).initialize(registry, clone, name, commitDeadline, revealDeadline, candidates, msg.sender);
        emit BordaCreated(clone);
        return clone;
    }
/*
    function createPRDhondt(
        string calldata name,
        uint64 commitDeadline,
        uint64 revealDeadline,
        string[] calldata partyNames,
        uint8 seats,
        uint16 thresholdBps
    ) external onlyOwner returns (address) {
        address clone = prImpl.clone();
        PRElectionDhondt(clone).initialize(registry, name, commitDeadline, revealDeadline, partyNames, seats, thresholdBps, msg.sender);
        emit PRCreated(clone);
        return clone;
    }*/

}