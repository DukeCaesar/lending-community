// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "./Fund.sol";
import "./../access/Roles.sol";
import "./../data/DataStructure.sol";

/**
 * @dev This contract manages the voting process of the mutual lending service. Whenever a customer applies for a loan,
  dozens of randomly selected lending fund providers representing the whole community will vote on this loan application to decide whether to confirm it or decline it.
 */
contract Voting is Roles, AccessControl, DataStructure, VRFConsumerBase {    
    struct Ballot {
        uint loanApplicationId; // the loan application to which the ballot is associated with
        address borrower; // the person who makes the loan application for loan
        uint confirmCount; // number of votes to confirm the loan application for loan request
        uint declineCount; // number of votes to decline this loan application
        // uint adjustCount; // number of votes to command the borrower to change his or her loan request, either by providing more documents or change the amount of loan
        uint votingCreateTime;
        uint votingEndTime; // the time when voting for this loan application ends
        BallotState state; 
        mapping(address => uint) votingTime; // record the time when each voter casts its vote
        mapping(address => bool) votingDecisions; // record each voter's voting decision
        mapping(address => bool) voters; // selected members who are granted the voting right for this loan application
    }
    
    /**
     @dev numVoters the default number of members of the decision committee for loan application.
     */    
    uint public numVoters = 12;

    uint private minimumNumVoters = 3; // the minimum number of voters for any loan application.

    uint private ballotCounter; // a counter to generate ballotId
    mapping(uint => Ballot) private ballots; // a mapping from ballotId to ballot data

    uint private minimumWindow = 86400; // the minimum time needed for the voting process. A default value can be set as one day, or perhaps one week, which will be a more reasonable value

    bytes32 internal keyHash;
    uint256 internal fee;
    mapping(bytes32 => uint) reqeustIdToBallotId; // Mapping Chainlink randomness requestId to ballotId.    

    event NoSuchBallot(uint indexed ballotId, address indexed voter);
    event BallotInFinishedState(uint indexed ballotId, address indexed voter);
    event VotingTimeExpired(uint indexed ballotId, address indexed voter, uint votingEndTime);
    event VoterHasVoted(uint indexed ballotId, address indexed voter, bool accept);
    event NewBallotCreated(address indexed borrower, uint ballotId);
    event RepetitiveVoting(address indexed voter, uint ballotId);
    event VotingRoleGranted(uint ballotId);
    event NumberOfVotersTooSmall(uint numberOfVoters);
    event NumberOfVotersUpdated(uint numberOfVoters);


    /**
     * Constructor inherits VRFConsumerBase
     * 
     *
     * Network: Rinkeby
     * Chainlink VRF Coordinator address: 0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B
     * LINK token address:                0x01BE23585060835E02B77ef475b0Cc51aA1e0709
     * Key Hash: 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311
     * Fee: 0.1 LINK
     *
     * Network: Kovan
     * Chainlink VRF Coordinator address: 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9
     * LINK token address:                0xa36085F69e2889c224210F603D836748e7dC0088
     * Key Hash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4
     * Fee: 0.1 LINK
     *
     * Network: Ethereum Mainnet
     * Chainlink VRF Coordinator address: 0xf0d54349aDdcf704F77AE15b96510dEA15cb7952
     * LINK token address:                0x514910771AF9Ca656af840dff83E8264EcF986CA
     * Key Hash: 0xAA77729D3466CA35AE8D28B3BBAC7CC36A5031EFDC430821C02BC31A238AF445
     * Fee: 2 LINK
     */
    constructor()
        VRFConsumerBase(
            0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B, // VRF Coordinator
            0x01BE23585060835E02B77ef475b0Cc51aA1e0709  // LINK Token
        )
    {
        // grant the admin_roles to contract creator
        grantRole(ADMIN_ROLE, msg.sender);

        keyHash = 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;
        fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)        
    }    

    /**
     * @dev Ramdonly selected members, representing the whole community, will vote on the loan application. The system works in a way similar to the US judicial system.
     * @param ballotId the ballot id
     * @param confirm whether the voter confirm or decline the loan application
       Only those members who are authorized for voting for this specific loan application can vote.
     */
    function vote(uint ballotId, bool confirm) public ballotExist(ballotId) {
        // 1. check the conditions of the ballot
        // 1.1 first check if the ballot with specified ballotId existed
        // the modifier ballotExist has done this verification

        // 1.2 check the state of the ballot
        require(ballots[ballotId].state != BallotState.FINISHED, "Voting: Voting for this ballot has ended.");
        // emit BallotInFinishedState(ballotId, msg.sender);

        // 1.3 check the ending time has not expired
        require(ballots[ballotId].votingEndTime > block.timestamp, "Voting: The end time for voting has passed.");
        // emit VotingTimeExpired(ballotId, msg.sender, ballots[ballotId].votingEndTime);
        
        // 1.4 check if the voter has already voted before.
        // This is to prevent voters to repetitive voting, or voting multiple times.
        require(ballots[ballotId].votingTime[msg.sender] == 0, "Voting: The voter has already voted before.");
        // emit RepetitiveVoting(msg.sender, ballotId);

        // 2. Effects of the vote
        // 2.1 record the voting time
        ballots[ballotId].votingTime[msg.sender] = block.timestamp;

        // 2.2 add the voter to the listing of voters who have already voted, and record their voting decisions
        ballots[ballotId].votingDecisions[msg.sender] = confirm;

        // 2.3 count the vote
        if(confirm) {
            ballots[ballotId].confirmCount++;
        } else {
            ballots[ballotId].declineCount++;
        }

        emit VoterHasVoted(ballotId, msg.sender, confirm);
    }

    /**
     * @dev Create a new ballot, where members can vote for a loan application for loan.
       @param borrower the member who makes the loan application
       @param votingWindow how long such voting will last
       @return uint the Id of the newly created ballot

       Only authorized roles can perform createBallot action
     */
    function createBallot(address borrower, uint votingWindow) public returns (uint) {
        require(votingWindow > minimumWindow, "Voting: The voting window is too short.");

        require(borrower > address(0), "Voting: The borrower's address is empty.");

        uint ballotId = ballotCounter ++;
        ballots[ballotId].borrower = borrower;
        ballots[ballotId].votingCreateTime = block.timestamp;
        ballots[ballotId].votingEndTime = ballots[ballotId].votingCreateTime + votingWindow;
        ballots[ballotId].state = BallotState.CREATED;

        emit NewBallotCreated(borrower, ballotId);

        return ballotId;
    }

    /**
     * @dev For any specific loan application, voters, who are responsible for making load decisions, are selected
      from qualified community members and voting roles are granted.
      Qualified community memebers refer to those who has a material interest in the community, which means they have invest a sizealbe assest in the community fund.
     * @param ballotId BallotId of the ballot for which qualified voters will be selected
     */
    function selectQualifiedVoters(uint ballotId) internal onlyRole(ADMIN_ROLE) ballotExist(ballotId) returns (address[] memory) {
        // first generate a random number
        // then use this generated number as an index to access the candidate
        bytes32 requestId = getRandomNumber();
        reqeustIdToBallotId[requestId] = ballotId;
    }

    /**
     * @dev Only selected qualified voters are granted the voting role for any specific loan application.
       Qualified community memebers refer to those who has a material interest in the community, which means they have invest a sizealbe assest in the community fund.
       @param ballotId ballotId of the ballot to which voting roles will be granted to qualified memebers.

       Only admin_roles can perform grantVotingRole action
     */
    function grantVotingRole(uint ballotId, address[] memory voters) public onlyRole(ADMIN_ROLE) ballotExist(ballotId) {

        for(uint i=0; i < voters.length; i ++) {
            address voter = voters[i];
            // grant the voting role to the voter for the ballot "ballotId"
            ballots[ballotId].voters[voter] = true;
        }

        emit VotingRoleGranted(ballotId);
    }    

    /**
     * @dev manipulations with ballot dictates that ballot must exist firt.
     * @param ballotId The ballotId for verifying its existence
     */
    modifier ballotExist(uint ballotId) {
        // first check if the ballot with specified ballotId existed
        address borrower = ballots[ballotId].borrower;
        require(borrower != address(0), "Voting: The specified ballot does not exist.");

        // emit NoSuchBallot(ballotId, msg.sender);
        _;        
    }

    /**
     * @dev Set a new number of voters for loan decision committee
       @param numberOfVoters The new number of voters
     */
    function setNumVoters(uint numberOfVoters) public onlyRole(ADMIN_ROLE) {
        require(numberOfVoters >= minimumNumVoters, "Voting: New number of voters is too small.");

        // emit NumberOfVotersTooSmall(numberOfVoters);

        numVoters = numberOfVoters;

        emit NumberOfVotersUpdated(numberOfVoters);
    }


    /** 
     * Requests randomness 
     */
    function getRandomNumber() public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Voting: Not enough LINK.");

        return requestRandomness(keyHash, fee);
    }    

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        // get the number of investors in the community
        Fund fund = new Fund();
        uint investorNum = fund.getInvestorCount();

        // Set the size for the index array

        // Generate random indexes for the investor array
        // The number of randomly generated indexes, which will be needed to select voters from the investor array for the loan approval
        uint[] memory indexes = new uint[](numVoters);
        // Getting multiple random numbers from a single VRF response, "investorNum" will be used as the range for the random number
        for (uint256 i = 0; i < numVoters; i++) {
            indexes[i] = (uint256(keccak256(abi.encode(randomness, i))) % investorNum) + 1;
        }   

        // get the ballotId from requestId
        uint ballotId = reqeustIdToBallotId[requestId];
        address[] memory voters = fund.getQualifiedVoters(indexes);
        grantVotingRole(ballotId, voters);
    }        

}