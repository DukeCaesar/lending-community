// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./../data/DataStructure.sol";
import "./LoanApplicationControl.sol";

/**
 * @author GeorgeQing
 * @dev Manages the fund of the mutual lending community
 */
contract Fund is DataStructure, AccessControl {
    mapping(address => uint) balances; 

    uint private vault; // the accumulated amount of the community

    event DepositSuccess(address indexed creditor);
    event WithdrawSuccess(address indexed creditor);

    bytes32 constant private ADMIN_ROLES = "admin_roles";

    uint interestRateReciprocal = 25;  // interest rate is 4 / 100 = 1 / interestRateReciprocal

    uint loanIdCounter;
    mapping(uint => Loan) loans; // mapping from loanId to Loan    

    mapping(uint => uint) applicationToLoan; // mapping from applicationId to loanId;

    /**
     * @dev Community members can invest into the lending fund and earn interests
     */
    function deposit() external payable {
        uint amount = msg.value;
        uint currentBalance = balances[msg.sender];
        balances[msg.sender] = currentBalance + amount;

        // update the total amount
        vault = vault + amount;

        emit DepositSuccess(msg.sender);
    }

    /**
     * @dev Community members can withdraw their fund
     */
    function withdraw(uint amount) external {
        require(balances[msg.sender] >= amount, "Fund: Balance insufficient for withdrawal.");

        uint currentBalance = balances[msg.sender];
        balances[msg.sender] = currentBalance - amount;

        // update the total amount
        vault = vault - amount;

        emit WithdrawSuccess(msg.sender);
    }

    /**
     * @dev Pay the reimbursement for the claim, i.e. paying out the fund requested by the claimer.
     * @param applicationId The id of the loan application
     * Only admin can call this function
     */
    function grantLoan(uint applicationId) public onlyRole(ADMIN_ROLES) {
        LoanApplicationControl applicationControl = new LoanApplicationControl();
        LoanApplication memory application = applicationControl.getApplication(applicationId);

        // check the state
        require(application.state == LoanApplicationState.APPROVED, "LoanApplication: The application is not ready for loan.");

        require(applicationToLoan[applicationId] == 0, "LoanApplication: A loan has already been granted for this application.");

        // Effects, to prevent reentry attack
        // application.state = LoanApplicationState.PAID;

        uint loanId = loanIdCounter ++;
        // mapping from applicationId to loanId;
        applicationToLoan[applicationId] = loanId;

        // Interactions
        // populate a loan struct with new data
          

        loans[loanIdCounter].borrower = application.borrower;
        loans[loanIdCounter].amountLoaned = application.amountApproved;
        loans[loanIdCounter].loanTerm = application.loanTerm;
        loans[loanIdCounter].grantTime = block.timestamp;
        loans[loanIdCounter].interestRateReciprocal = interestRateReciprocal;

        // Usually the number of installment equals loan term. 
        // a 6 month term equals 6 installments. However, in future, installments could be twice of loan terms
        loans[loanIdCounter].installment = application.loanTerm; 

        loans[loanIdCounter].amountDue = application.amountApproved;
        loans[loanIdCounter].interestPaid = 0;

        address payable borrower = payable(application.borrower);

        uint amountLoaned = loans[loanIdCounter].amountLoaned;

        require(address(this).balance > amountLoaned, "LoanApplication: There is not enough fund in the community pool for paying out the borrower.");

        // This forwards all available gas. Be sure to check the return value!
        (bool success, ) = borrower.call{value: amountLoaned}("");

        require(success, "LoanAction: Transfer loan to borrower has failed.");     
    }    
}