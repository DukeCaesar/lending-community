// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DataStructure {
    struct MemberData {
        bool membership;
        uint joinTime;
        uint refreshTime; // last time when the user refresh its membership
        uint accumulatedReimbursement;
        uint totalExpense; // the total amount of expenses the member has already paid
    }    

    /**
     * NONEXISTENT: this is the default state for this enum
     * REQUESTED: this loan has been proposed by a member
     * APPROVED: this loan has been approved by DAO
     * DELINED: this loan has been denied by DAO
     * PENDING: this loan has been in pending state, for instance more documents need to be provided to prove for eligibility
     * PAID: this loan has been paid for by the community fund
     */
    enum LoanApplicationState {
        NONEXISTENT, 
        CREATED, 
        WAITINGFORAPPROVAL,
        MOREDOCUMENTSNEEDED,
        APPROVED, 
        DELINED, 
        PAID
    }    

    // the Loan struct contains the data of each loan
    struct LoanApplication {
        address borrower;
        uint amountLoaned; // the amount loaned by the borrower
        uint loanTerm; // the duration of the loan
        uint applicationTime;
        LoanApplicationState state; // the state of the loan application
        uint amountApproved; // the final amount approved by the community
        uint approvalTime;
    }    

    struct Loan {
        address borrower;
        uint amountLoaned; // the amount loaned by the borrower                
        uint loanTerm; // the duration of the loan, in terms of months.
        uint installment; // the number of installment that borrower will need to pay back the full loan
        uint grantTime; // the time when the loan has been granted to the borrower
        uint amountDue; // the amount of the loan which remains to be returned by the borrower
        uint interestRateReciprocal; // the interest rate on the loan
        uint interestPaid; // the aggregate interests paid by the borrower
    }
}