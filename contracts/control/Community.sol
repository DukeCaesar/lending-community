//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../data/DataStructure.sol";
import "./../access/Roles.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @author George Qing, Jieshu Tech. Ltd.
 * @dev This contract manages the membership of this community. Candidate can join or leave the community.
 */
contract Community is Roles, DataStructure, AccessControl {

    mapping(address => MemberData) private members;

    uint private memberCount;

    // mapping(address => uint) private reimbursements;
    // mapping(address => uint) private expenses;

    // mapping(address => ReimbursementData[]) private reimbursementRecords; // the variable contains the list of reimbursement paid by each member
    
    uint private waitingTime; // the time duration before a member can make any claims for reimbursement.

    event JoinedCommunity(address indexed applicant);
    event LeftCommunity(address indexed applicant);
    event StillInWaitingTime(address indexed applicant, uint joinTime, uint waitingTime);
    event PaymentReceived(address indexed payer, uint amount);
    event MembershipRefreshed(address indexed member);

    constructor() {
        // When a contract is created, its constructor is executed once.
        // grant the admin_roles to contract creator
        // Here can be problematic 这儿会有问题
        grantRole(ADMIN_ROLES, msg.sender);
    }

    /**
     * @dev The receive function is executed on a call to the contract with empty calldata. 
     This is the function that is executed on plain Ether transfers (e.g. via .send() or .transfer()).
     */
    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

    /**
     * @dev join the community of mutual insurance
     */
    function joinCommunity() external returns (bool) {
        // check if msg.sender has already joined the community
        require(!members[msg.sender].membership, "Community: Already a member." );

        members[msg.sender].membership = true;
        members[msg.sender].joinTime = block.timestamp;

        memberCount ++;

        emit JoinedCommunity(msg.sender);

        return true;
    }

    /**
     * @dev leave the community of mutual insurance
     */
    function leaveCommunity() external onlyMember returns (bool) {

        members[msg.sender].membership = false;
        delete members[msg.sender].joinTime;

        memberCount --;

        emit LeftCommunity(msg.sender);

        return true;
    }

    /**
     * @dev get the number of members in the community
     */
    function getMemberCount() external view returns (uint) {
        return memberCount;
    }

    /**
     * @dev only member can call the function
     */
    modifier onlyMember {
        require(members[msg.sender].membership, "Community: Not a member yet.");
        _;
    }

    /**
     * @dev set the waiting period for a new member before he or she can apply for loans. Only allowed for administrative roles.
     */
    function setWaitingTime(uint _waitingTime) external onlyRole(ADMIN_ROLES) {
        waitingTime = _waitingTime;
    }

    /**
     * @dev Check if the waiting time has already passed.
     If the waiting period is over, member is allowed to apply for loans.
     Otherwise, an error message will be sent back.
     * @param borrower the member who apply for a loan
     */
    function checkIncubation(address borrower) public view onlyMember {
        require(borrower != address(0), "Community: The borrower address is empty.");

        uint currentTime = block.timestamp;
        uint joinTime = members[borrower].joinTime;

        require(currentTime > (joinTime + waitingTime), "Community: Borrower is still in waiting time and not allowed to apply for loans yet.");
    }   
}