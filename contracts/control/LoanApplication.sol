// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./../data/DataStructure.sol";
import "./Community.sol";
import "./Fund.sol";
import "./../access/Roles.sol";

/**
 * @author George Qing, Jieshu Tech. Ltd.
 * @dev This contract manages the applications made by community members.
 */

contract LoanApplication is Roles, DataStructure, AccessControl {
    uint private applicationIdCounter; 

    mapping(uint => Application) private applications;    

    mapping(address => Application) private pendingLoans; // the exising applications which has not been finished yet.

    uint private maximumAmount; // the maximum amount allowed for any loan

    uint private maximumTerm; // the maximum term allowed for any loan

    event LoanApplicationCreated(address indexed borrower, uint applicationId);
    event RequestMoreProof(address indexed borrower, uint applicationId);
    event MoreProofProvided(address indexed borrower, uint applicationId);
    event ApplicationDeclined(address indexed borrower, uint applicationId);
    event ApplicationApproved(address indexed borrower, uint applicationId);
    event MaximumTermSet(address indexed sender, uint term);

    constructor() {
        // When a contract is created, its constructor is executed once.
        // grant the admin_roles to contract creator
        // Here can be problematic 这儿会有问题
        grantRole(ADMIN_ROLES, msg.sender);
    }
    
    /**
     * @dev member apply for a loan.
      @param amount the amount for loan
     */
    function createLoanApplication(uint amount, uint loanTerm) external {

        require(amount > 0, "LoanApplication: The loaned amount is zero.");

        require(amount <= maximumAmount, "LoanApplication: The loan amount has exceeded the maximum amount allowed for any member.");

        require(loanTerm < maximumTerm, "LoanApplication: The term of loan has exceeded the maximum term allowed for any member..");

        // Check if the waiting time has already passed.
        checkIncubation(msg.sender);

        applicationIdCounter ++;
        
        // create a new loan and record its data
        uint applicationId = applicationIdCounter;
        applications[applicationId].state = ApplicationState.CREATED;
        applications[applicationId].borrower = msg.sender;
        applications[applicationId].applicationTime = block.timestamp;
        applications[applicationId].loanTerm = loanTerm;
        applications[applicationId].amountLoaned = amount;

        emit LoanApplicationCreated(msg.sender, applicationId);

        // calculate the shared expense for each member, register the shared expense for each member and deduct the accumulated amount from member's account once every month
        // This approach entails traversing all members in the community.
        // As the number of members in the community grows, this traversing can be expensive in terms of gas, and it is highly likely that it could run out of gas in transaction
    }

    /**
     * @dev Check if the waiting time has already passed.
     If the waiting period is over, member is allowed to make applications for reimbursement.
     Otherwise, an error message will be sent back.
     */
    function checkIncubation(address borrower) internal {
        Community community = new Community();
        community.checkIncubation(borrower);
    }    

    /**
     * @dev Approve the loan.
     * Only admin can call this function
     */    
    function approveLoan(uint applicationId, uint amountApproved) external onlyRole(ADMIN_ROLES) {
        // Check
        // The default state is ApplicationState.NONEXISTENT.
        require(applications[applicationId].state == ApplicationState.WAITINGFORAPPROVAL, "LoanApplication: The specified loan with Id does not exist.");

        // Effects
        applications[applicationId].state = ApplicationState.APPROVED;
        applications[applicationId].approvalTime = block.timestamp;
        applications[applicationId].amountApproved = amountApproved;

        // Action

        emit ApplicationApproved(applications[applicationId].borrower, applicationId);
    }

    /**
     * @dev Decline the loan.
     * Only admin can call this function
     */
    function declineLoan(uint applicationId) external {
        // Check
        require(applications[applicationId].state == ApplicationState.WAITINGFORAPPROVAL, "LoanApplication: The specified loan with Id does not exist.");

        applications[applicationId].state = ApplicationState.DELINED;
        applications[applicationId].approvalTime = block.timestamp;

        emit ApplicationDeclined(applications[applicationId].borrower, applicationId);
    }

    /**
     * @dev Request borrower to provide more proof for his or her loan.
     */
    function requestMoreProof(uint applicationId) external {
        require(applications[applicationId].state == ApplicationState.WAITINGFORAPPROVAL, "LoanApplication: The specified loan with Id does not exist.");

        applications[applicationId].state = ApplicationState.MOREDOCUMENTSNEEDED;

        emit RequestMoreProof(applications[applicationId].borrower, applicationId);
    }

    /**
     * @dev Loaner provide more proof for his or her loan and request for approval decision
     */
    function provideMoreProof(uint applicationId) external {
        require(applications[applicationId].state == ApplicationState.MOREDOCUMENTSNEEDED, "LoanApplication: The specified loan is not in the right state.");

        applications[applicationId].state = ApplicationState.WAITINGFORAPPROVAL;

        emit MoreProofProvided(applications[applicationId].borrower, applicationId);
    }    

    /**
     * @dev Set the maximum term allowed for any loan.
     * Only admin can call this function
     */
    function setMaximumTerm(uint term) public onlyRole(ADMIN_ROLES) {
        maximumTerm = term;

        emit MaximumTermSet(msg.sender, term);
    }

    /**
     * @dev Get the maximum term allowed for any loan.
     */
    function getMaximumTerm() public view returns(uint) {
        return maximumTerm;
    }

    /**
     * @dev Get the load application by the applicationId
     * @param applicationId Application Id for which details will be retrieved
     */
     //  Data location must be "memory" or "calldata" for return parameter in function, but "storage" was given.
    function getApplication(uint applicationId) public view returns(Application memory) {
        // Check if the application of this id exist
        require(applications[applicationId].state != ApplicationState.NONEXISTENT, "LoanApplication: The specified loan with Id does not exist.");    

        return applications[applicationId];
    }

}