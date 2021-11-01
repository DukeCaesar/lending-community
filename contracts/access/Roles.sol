//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev This contract defines roles for access control
 */
contract Roles {
    bytes32 constant public ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant public MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 constant public VOTING_ROLE = keccak256("VOTING_ROLE"); // Roles for committee members who can vote for a specific loan application
}