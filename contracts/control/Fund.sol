// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./../data/DataStructure.sol";
import "./LoanApplication.sol";

/**
 * @author GeorgeQing
 * @dev Manages the fund of the mutual lending community
 */
contract Fund is DataStructure, AccessControl {
    mapping(address => uint) balances; 

    uint private vault; // the accumulated amount of the community

    event DepositSuccess(address indexed creditor);
    event WithdrawSuccess(address indexed creditor);
    event PaymentReceived(address indexed payer, uint amount);
    event LoanRepaymentSuccess(uint loanId, address indexed borrower, uint amount);
    event LoanFullyRepaid(uint loanId, address indexed borrower);

    bytes32 constant private ADMIN_ROLES = "admin_roles";

    uint interestRate = 20;  // the default daily interest rate, unit being 1 divided by a hundred thousand

    uint idCounter;
    mapping(uint => Loan) loans; // mapping from loanId to Loan    

    mapping(uint => uint) applicationToLoan; // mapping from applicationId to loanId;

    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

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
        LoanApplication loanApplication = new LoanApplication();
        Application memory application = loanApplication.getApplication(applicationId);

        // check the state
        require(application.state == ApplicationState.APPROVED, "Fund: The application is not ready for loan.");

        require(applicationToLoan[applicationId] == 0, "Fund: A loan has already been granted for this application.");

        // Effects, to prevent reentry attack
        // application.state = ApplicationState.PAID;

        uint loanId = idCounter ++;
        // mapping from applicationId to loanId;
        applicationToLoan[applicationId] = loanId;

        // Interactions
        // populate a loan struct with new data
          

        loans[idCounter].borrower = application.borrower;
        loans[idCounter].amountLoaned = application.amountApproved;
        loans[idCounter].loanTerm = application.loanTerm;
        loans[idCounter].grantTime = block.timestamp;
        loans[idCounter].interestRate = interestRate;

        // Usually the number of installment equals loan term. 
        // a 6 month term equals 6 installments. However, in future, installments could be twice of loan terms
        loans[idCounter].installment = application.loanTerm; 

        loans[idCounter].amountDue = application.amountApproved;
        loans[idCounter].interestPaid = 0;

        address payable borrower = payable(application.borrower);

        uint amountLoaned = loans[idCounter].amountLoaned;

        require(address(this).balance > amountLoaned, "Fund: There is not enough fund in the community pool.");

        // This forwards all available gas. Be sure to check the return value!
        (bool success, ) = borrower.call{value: amountLoaned}("");

        require(success, "Fund: Transfer loan to borrower has failed.");     
    }    

    /**
     * @dev Borrowers call this function to repay their loans
     */
    function repayLoan(uint loanId) external payable {
        // Check if loan with this loanId does exist or not
        require(loans[loanId].borrower != address(0), "Fund: Loan does not exist.");

        // Ensure that loan borrower is the same as the repayer.
        // In future, it be allowed for other members to repay a loan on behalf of a borrower
        require(loans[loanId].borrower == msg.sender, "Fund: Payer is different from loan borrower.");

        // calculate the days lapsed, block.timestamp (uint): block timestamp as seconds since unix epoch
        uint daysLapsed = (block.timestamp - loans[loanId].grantTime) % 86400;

        // calculate the interest until this repayment
        uint interest = uint(loans[loanId].amountDue * daysLapsed * loans[loanId].interestRate / 100000);

        // calculate the principle per installment that needs to be repaied
        uint principal = uint(loans[loanId].amountLoaned / loans[loanId].installment);

        // Ensure repayment should be sufficient to cover both principal and interest
        require(msg.value >= (principal + interest), "Fund: Repayment is too small.");

        uint principalRepayed = msg.value - interest;

        // update te loan information
        loans[loanId].interestPaid += interest;

        if (loans[loanId].amountDue > principalRepayed) {
            loans[loanId].amountDue -= principalRepayed;
        } else {
            // loans[loanId].amountDue =< principalRepayed, meaning borrower has repaid more than needed.
            loans[loanId].amountDue = 0;
            loans[loanId].fullyRepaid = true;
            emit LoanFullyRepaid(loanId, msg.sender);
        }
        
        loans[loanId].installmentRepaid ++;

        emit LoanRepaymentSuccess(loanId, msg.sender, msg.value);
    }
}