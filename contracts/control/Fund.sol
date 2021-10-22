// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./../data/DataStructure.sol";
import "./LoanApplication.sol";
import "./../access/Roles.sol";

/**
 * @author GeorgeQing
 * @dev Manages the fund of the mutual lending community
 */
contract Fund is Roles, DataStructure, AccessControl {
    mapping(address => uint) balances; 
    address[] investors; // record the members who has deposited money into the community
    mapping(address => uint) investorIndexes; // the index of each investor in the investors array
    uint startIndex; // the starting index when distributing interest income

    mapping(address => uint) depositTime; // record the last time when the member made a deposit

    uint public depositLockTime = 86400; // the time when a new deposit will be locked up and prevented from withdrawn. The default value is 1 day = 86400 seconds. This can be modified by admin

    uint public vault; // the accumulated amount deposited by the community
    uint public loanOutstanding; // the sum of loans outstanding
    uint public interestsReceived; // the interests received from borrowers, and not yet distributed to members
    uint public provision; // provision for bad and doubtful loans

    uint public accruedLoans; // the sum of all loans lent out to members since operation
    uint public accruedInterests; // the sum of all interests received since operation

    event DepositSuccess(address indexed creditor);
    event WithdrawSuccess(address indexed creditor);
    event PaymentReceived(address indexed payer, uint amount);
    event LoanRepaymentSuccess(uint loanId, address indexed borrower, uint amount);
    event LoanGranted(uint loanId, uint amount, address indexed borrower);
    event LoanFullyRepaid(uint loanId, address indexed borrower);
    event DepositLockTimeUpdated(uint oldLockTime, uint newLockTime);
    event InterestDistributed(uint amount);

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

        // add this new investor to the investors array
        if (currentBalance == 0) {
            // first record the index of the specific address in the investor array, so that future retrieval by address is possible
            uint size = investors.length;
            investorIndexes[msg.sender] = size;
            // then add to investor array
            investors.push(msg.sender);
        }

        balances[msg.sender] = currentBalance + amount;

        // update the total amount
        vault = vault + amount;

        // record the deposit time for this member
        depositTime[msg.sender] = block.timestamp;

        emit DepositSuccess(msg.sender);
    }

    /**
     * @dev Community members can withdraw their fund
     * @param amount The amount to withdraw
     */
    function withdraw(uint amount) external {
        require(amount > 0, "Fund: Withdraw amount should not be zero.");

        require(balances[msg.sender] >= amount, "Fund: Balance insufficient for withdrawal.");

        require(block.timestamp > (depositTime[msg.sender] + depositLockTime), "Fund: Withdrawal is close to a recent deposit.");

        uint currentBalance = balances[msg.sender];
        balances[msg.sender] = currentBalance - amount;

        // remove this investor to the investors array
        if (balances[msg.sender] == 0) {
            // retrieve array index for this investor
            uint index = investorIndexes[msg.sender];
            address last = investors[investors.length-1];
            // to remove from the end of the array.
            investors.pop();
            // replace the withdrawing investor with the last one in the array, therefore removing the possibility of empty slot in the investors array
            investors[index] = last;
        }

        // update the total amount
        vault = vault - amount;

        emit WithdrawSuccess(msg.sender);
    }

    /**
     * @dev Set the lock time for a deposit. The deposit can only be withdrawn after the lock time
     * @param lockTime The new lock time.
     */
    function setDepositLockTime(uint lockTime) public onlyRole(ADMIN_ROLES) {
        require(lockTime > depositLockTime, "Fund: The new lock time is smalller than the default value.");
        uint oldLockTime = depositLockTime;
        depositLockTime = lockTime;

        emit DepositLockTimeUpdated(oldLockTime, depositLockTime);
    }

    /**
     * @dev Grant the loan to the borrower.
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

        // update the total amount
        vault -= amountLoaned;
        loanOutstanding += amountLoaned;
        accruedLoans += amountLoaned;

        // This forwards all available gas. Be sure to check the return value!
        (bool success, ) = borrower.call{value: amountLoaned}("");

        require(success, "Fund: Transfer loan to borrower has failed.");     

        emit LoanGranted(loanId, amountLoaned, loans[idCounter].borrower);
    }    

    /**
     * @dev Borrowers call this function to repay their loans
     * @param loanId The loan to be repaid
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

        // update the total amount
        vault += principalRepayed;
        // update the loan outstanding
        loanOutstanding -= principalRepayed;
        accruedInterests += interest;

        emit LoanRepaymentSuccess(loanId, msg.sender, msg.value);
    }

    /**
     * @dev Interest income is distributed among investors who have deposited fund into the community
     */
    function distributeInterest() external payable onlyRole(ADMIN_ROLES) returns(bool completed){
        require(interestsReceived > 0, "Fund: No interests to be distributed yet.");

        uint investorNum = investors.length;
        uint endIndex = investors.length - 1;

        // In order to present gas depletion, curb the maximum iteration to 100
        if ((investorNum - 1 - startIndex) > 99) {
            endIndex = startIndex + 99;
            completed = false;
        } else {
            completed = true;
        }
        
        for (uint i=startIndex; i<=endIndex; i++) {
            // calculate the share of interest income for each investor
            address investor = investors[i];
            uint interestShare = uint(interestsReceived * balances[investor] / vault);

            // This forwards all available gas. Be sure to check the return value!
            (bool success, ) = investor.call{value: interestShare}("");

            require(success, "Fund: Transfer interest income to investor has failed.");                 
        }
        
        if (completed) {
            // reset the startIndex
            startIndex = 0;

            emit InterestDistributed(interestsReceived);
            // reset the interestsReceived, since all interests received have been distributed to investors
            interestsReceived = 0;
            
        } else {
            // update startIndex for next call of this function 
            startIndex = endIndex + 1;
        }
        
    }
}