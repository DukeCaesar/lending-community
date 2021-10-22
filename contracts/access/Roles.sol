//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @dev This contract defines roles for access control
 */
contract Roles {
    bytes32 constant public ADMIN_ROLES = "admin_roles";
    bytes32 constant public MEMBER_ROLES = "member_roles";
    bytes32 constant public VOTING_ROLES = "voting_roles"; // Roles for committee members who can vote for a specific loan application
}