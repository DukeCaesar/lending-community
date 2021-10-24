# lending-community

 A lending community where members can apply for a credit loan by submitting their geneuine identities and proof of social capitals, and randomly selected members can vote on the loan applications. Any profits generated from interest income are distributed among community members based on their shares of capital invested.

 When interests are paid by borrowers, first a small percentage is deducted and this money will go directly to the provisional funds, which will be used to cover bad and doubtful loans. Then the rest of interests will be distributed among community members based on their shares of capital invested.

 The share of profit generated from loan interests is calculated by dividing member's balance by the aggregate sum of investmemt.

 A combination of smarts contracts has been written to represent the whole process, each with a specific purpose. The core contracts are described below:
 1. Community contract is to control community related actions, such as joining or leaving the community;
 2. LoanApplication contract is to manage the application process of any loan. The decision committee can approve or clain a loan application, or require the applicant to provide more proofs for their social capitals.
 3. Voting contract is to control the voting process of by the decision committee members. The voters for any specific application are selected randomly from memmbers who have invested capital into the fund. Chainlink is utilized to generate random numbers for this purpose. Voting roles are then assigned to these voters by using access control from OpenZeppelin.
 4. Fund contract is to manage the financial aspect of the community. Members can deposit capitals into or withdraw capitals from the community fund. After a loan application is approved by the decision committee, the loan is granted to the borrower. When a loan is paid back, profits generated from interest income are distributed among community members.

 Malicious members encroaching interests income:
 There is a small pitful of this method: malicious members could deposit a tremendous amount of money before the interest payback day, therefore expanding their investment shares greatly and encroaching interests income of other righteous members. After the interests income are calculated based on investment shares and distributed, these malicious members withdraw their money back. These behaviours are impossible to prevent.

 One solution is to lock the deposit for a fixed period of time (for instance, one day or one week) before it can be withdrawn. During the locked-up time, there is the possibility that the huge investment may be lent out, and these malicious interest skimmers are facing the risk that they may not be able to withdraw their money back after the interest distribution, as there is not enough fund left in the vault. This could act as a deterrent to these behaviours. Therefore the lock-up time for deposit shall be long enough to accommodate the loan approval process.
