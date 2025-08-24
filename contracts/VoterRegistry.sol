
/*pragma solidity ^0.8.20;

import "./Ownable.sol";

contract VoterRegistry is Ownable {
    uint256 public constant MAX_VOTERS = 2000;
    mapping(bytes32 => bool) public isRegisteredIC;   // ic => registered
    uint256 public totalRegistered;

    event IdentityCommitmentAdded(bytes32 ic);
    event IdentityCommitmentRemoved(bytes32 ic);

    function addIdentityCommitments(bytes32[] calldata ics) external onlyOwner {
        require(totalRegistered + ics.length <= MAX_VOTERS, "VoterRegistry: exceeds max voters");
        for (uint i = 0; i < ics.length; i++) {
            bytes32 ic = ics[i];
            require(ic != bytes32(0), "VoterRegistry: zero ic");
            if (!isRegisteredIC[ic]) {
                isRegisteredIC[ic] = true;
                totalRegistered += 1;
                emit IdentityCommitmentAdded(ic);
            }
        }
    }

    function removeIdentityCommitments(bytes32[] calldata ics) external onlyOwner {
        for (uint i = 0; i < ics.length; i++) {
            bytes32 ic = ics[i];
            if (isRegisteredIC[ic]) {
                delete isRegisteredIC[ic];
                totalRegistered -= 1;
                emit IdentityCommitmentRemoved(ic);
            }
        }
    }
}*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Ownable.sol";

contract VoterRegistry is Ownable {
    // electionId => (ic => registered?)
    mapping(uint256 => mapping(bytes32 => bool)) private isRegisteredIC;

    // electionId => list of all ICs ever registered
    mapping(uint256 => bytes32[]) private registeredICs;

    // electionId => (ic => wallet address that registered it)
    mapping(uint256 => mapping(bytes32 => address)) private icOwner;

    // Dummy switch: only when true can new registrations happen
    bool public registrationOpen = true;

    event IdentityCommitmentAdded(uint256 indexed electionId, bytes32 ic, address registrant);
    event IdentityCommitmentRemoved(uint256 indexed electionId, bytes32 ic, address removedBy);

    /// @notice Allow anyone to register themselves for an election
    function register(uint256 electionId) external returns (bool success) {
        require(registrationOpen, "Registration is closed");
        bytes32 ic = keccak256(abi.encodePacked(msg.sender, electionId));
        require(!isRegisteredIC[electionId][ic], "Already registered");

        // Register IC
        isRegisteredIC[electionId][ic] = true;
        registeredICs[electionId].push(ic);
        icOwner[electionId][ic] = msg.sender;

        emit IdentityCommitmentAdded(electionId, ic, msg.sender);
        return true;
    }

    /// @notice Allow owner or the original registrant to deregister
    function deregister(uint256 electionId) external returns (bool success) {
        bytes32 ic = keccak256(abi.encodePacked(msg.sender, electionId));
        require(isRegisteredIC[electionId][ic], "Not registered");
        require(
            msg.sender == owner || msg.sender == icOwner[electionId][ic],
            "Not authorized to deregister"
        );

        isRegisteredIC[electionId][ic] = false;
        emit IdentityCommitmentRemoved(electionId, ic, msg.sender);
        return true;
    }

    /// @notice Get full voter history for an election
    function getAllICs(uint256 electionId) external view returns (bytes32[] memory) {
        return registeredICs[electionId];
    }

    /// @notice Get only active voters for an election
    function getActiveICs(uint256 electionId) external view returns (bytes32[] memory) {
        bytes32[] storage all = registeredICs[electionId];
        uint count = 0;

        for (uint i = 0; i < all.length; i++) {
            if (isRegisteredIC[electionId][all[i]]) {
                count++;
            }
        }

        bytes32[] memory actives = new bytes32[](count);
        uint idx = 0;
        for (uint i = 0; i < all.length; i++) {
            if (isRegisteredIC[electionId][all[i]]) {
                actives[idx++] = all[i];
            }
        }

        return actives;
    }

    /// @notice Check whether an IC is currently active in an election
    function isActive(uint256 electionId, bytes32 ic) external view returns (bool) {
        return isRegisteredIC[electionId][ic];
    }

    /// @notice Owner can toggle global registration switch
    function setRegistrationOpen(bool open) external onlyOwner {
        registrationOpen = open;
    }
}
