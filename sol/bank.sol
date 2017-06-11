pragma solidity ^0.4.11;
import './token.sol';

contract LyonBank is StandardToken {
    
    enum Role {
        unregistered,
        registered,
        manager
    }

    struct Transaction {
        address[] votes;
        address from;
        address to;
        uint amount;
    }

    struct ChangeManager {
        address[] votes;
        address from;
        address to;
    }

    // allows the "to" address withdraw multiple times 
    // using the transferFrom function up to the specified limit
    // a successfully voted allowance += the amount
    // in the allowed[from][to] entry
    struct Allowance {
        address[] votes;
        address from;
        address to;
        uint allowance;
    }

    /*
        MODIFIERS
    */
    
    modifier isManager() {
        require(memberRoles[msg.sender] == Role.manager);
        _;
    }
    
    modifier isMember() {
        require(memberRoles[msg.sender] != Role.unregistered);
        _;
    }
    
    modifier isOpen() {
        require(open);
        _;
    }
    
    modifier hasEnoughTokens(address user, uint amount) {
        require(balances[user] >= amount && amount > 0);
        _;
    }
    
    modifier transactionExists(uint actionId) {
        require(transactions.length > actionId);
        _;
    }

    modifier managerChangeExists(uint managerChangeId) {
        require(managerChanges.length > managerChangeId);
    }

    modifier hasntVoted(address[] voters) {
        for (uint8 i = 0; i < voters.length; i++) {
            assert(msg.sender != voters[i]);
        }
        _;
    }
    
    // token info
    string public name;                 // token name
    string public symbol;               // token symbol
    uint8 public decimals = 18;         // same decimals as ether
    string public version = 'LB-0.1';   // version number

    // vote info
    uint8 maxManagers; // maximum managers
    uint8 minVotes; // minimum votes to confirm an action
    
    
    function LyonBank(
        uint256 _initialAmount,
        string _tokenName,
        string _tokenSymbol, 
        
        uint8 _managers, 
        uint8 _majority) {
            
        balances[address(this)] = _initialAmount; // give the bank all the tokens
        totalSupply = _initialAmount; // set the total supply
        name = _tokenName; // set the name
        symbol = _tokenSymbol; // set the sumbol
            
        members.push(msg.sender); // add the contract creator as a member
        memberRoles[msg.sender] = Role.manager; // set the address to manager
        maxManagers = _managers; // set the manager cap
        minVotes = _majority; // set the minimum consensus
        
        open = true;
    }

    /*
        EVENTS
    */

    // managers
    event CreateManagerChange(uint changeManagerId, address from, address to);
    event ApproveManagerChange(uint changeManagerId, address user);
    event CompletedManagerChange(uint changeManagerId, address[] approvers);
    
    ChangeManager[] managerChanges;

    // members
    event MemberAdded(address user);
    event MemberRemoved(address user);

    address[] members; // members

    mapping(address => Role) memberRoles; // which address has what role

    // token transactions
    event CreateTransaction(uint transactionId, address from, address to, uint amount);
    event ApprovedTransaction(uint transactionId, address user);
    event CompletedTransaction(uint transactionId, address[] approvers);
    event Deposit(address user, uint amount);

    Transaction[] transactions;

    // allowances
    event CreateAllowance(uint allowanceId, address from, address to, uint amount);
    event ApprovedAllowance(uint allowanceId, address user);
    event CompletedAllowance(uint allowanceId, address[] approvers);

    Allowance[] allowences;

    // self-distruct
    event SelfDistructVote(address user);
    
    address[] selfdistruct;
    bool open; // selfdistruct killswitch stops transactions/deposits

    // the bank may empty all accounts and refund all deposits, stopping all future transactions.
    function selfDistruct() isManager hasntVoted(selfdistruct) {
        selfdistruct.push(msg.sender);
        SelfDistructVote(msg.sender);
        
        // if enough votes, refund everyone and close bank
        if (selfdistruct.length >= minVotes) {
            for (uint j = 0; j < members.length; j++) {
                members[j].transfer(balances[members[j]]);
                balances[members[j]] = 0;
            }
            
            open = false;
        }
    }

    /* 
        TRANSACTIONS
    */
    
    // private, creates a transaction to be approved by managers
    function createTransaction(address _from, address _to, uint _amount) returns (uint transactionId) {
        transactions.push(Transaction({votes: new address[](0), from: _from, to: _to, amount: _amount})); // push the transaction
        CreateTransaction(transactions.length-1, msg.sender, _amount); // signal the event
        return transactions.length-1;
    }
    
    // allows managers to approve specified transaction ids
    function approveTransaction(uint transactionId) isManager transactionExists(transactionId) hasntVoted(transactions[transactionId].votes) {
        transactions[transactionId].votes.push(msg.sender); // add the vote to the transaction
        ApprovedTransaction(transactionId, msg.sender); // send out the vote event
        
        if (transactions[transactionId].votes.length >= minVotes) { // if we have enough votes
            completeTransaction(transactionId); // complete the transaction
        }
    }
    
    // completes a transaction
    function completeTransaction(uint transactionId) private transactionExists(transactionId) {
        require(transactions[transactionId].votes.length >= minVotes); // double check that there are enough votes!

        // call the function to actually transfer the tokens. (can only be called from this function)
        transferTokens(transactions[transactionId].from, transactions[transactionId].to, transactions[transactionId].amount);
        
        // if the transaction successfully transferred tokens back into the bank
        // it is a withdrawal and the equivalent ether should be returned to the account holder
        if (transactions[transactionId].to == address(this)) {
            transactions[transactionId].from.transfer(transactions[transactionId].amount);
        }
        
        CompletedTransaction(transactionId, transactions[transactionId].votes); // send a completion event
    }
    
    // transfers the tokens
    function transferTokens(address from, address to, uint amount) private isOpen hasEnoughTokens(from, amount) {
        balances[from] -= amount;
        balances[to] += amount;
        Transfer(from, to, amount);
    }
    
    /*
        MANAGEMENT CHANGE
    */

    function createManagementVote(address from, address to) isManager {
        require(memberRoles[from] == Role.manager); // the replacee is a manager
        require(memberRoles[to] != Role.manager); // the replacer is not a manager

        ChangeManager memory mr = ChangeManager({votes: new address[](0), from: from, to: to});
        managerChanges.push(mr);
        CreateManagerChange(managerChanges.length-1, from, to);

        // since you must be a manager to create the vote, it is assumed you want to vote for it as well.
        approveManagementVote(managerChanges.length-1);
    }

    function approveManagementVote(uint changeManagerId) isManager managerChangeExists(changeManagerId) hasntVoted(managerChanges[changeManagerId].votes) {
        managerChanges[changeManagerId].votes.push(msg.sender); // add the vote to the transaction
        ApproveManagerChange(changeManagerId, msg.sender); // send out the vote event
        
        if (managerChanges[changeManagerId].votes.length >= minVotes) { // if we have enough votes
            completeManagementVote(changeManagerId); // complete the transaction
        }
    }
    
    function completeManagementVote(uint changeManagerId) private isManager managerChangeExists(changeManagerId) {
        ChangeManager memory mc = managerChanges[changeManagerId];

        require(memberRoles[mc.from] == Role.manager); // the replacee is a manager
        require(memberRoles[mc.to] != Role.manager); // the replacer is not a manager

        memberRoles[mc.from] = Role.registered;
        memberRoles[mc.to] = Role.manager;

        CompletedManagerChange(changeManagerId);
    }

    /*
        DEPOSIT / WITHDRAW / TRANSFER
    */
    
    // deposit ether and give out tokens
    function () isMember payable hasEnoughTokens(address(this), msg.value) {
        transferTokens(address(this), msg.sender, msg.value);
    }
    
    // create a transaction to withdraw the ether and return tokens
    function withdraw(uint amount) hasEnoughTokens(msg.sender, amount) returns (bool success) {
        createTransaction(msg.sender, address(this), amount);
        return true;
    }
    
    // create a transaction to transfer tokens to another member
    function transfer(address _to, uint256 _value) hasEnoughTokens(msg.sender, amount) returns (bool success) {
        createTransaction(msg.sender, _to, _value);
        return true;
    }

    /*
        SET / REMOVE ALLOWANCE
    */

    function createAllowanceVote(address from, address to, uint amount) returns (uint allowanceId) {
        allowances.push(Allowance({votes: new address[](0), from: from, to: to, allowance: amount}));
        CreateAllowance(allowances.length-1, from, to, amount);
        return allowances.length-1
    }

    function approveAllowanceVote(uint allowanceId) isManager allowanceExists(allowanceId) hasntVoted(allowances[allowanceId].votes) {
        allowances[allowanceId].votes.push(msg.sender);
        ApprovedAllowance(allowanceId, msg.sender);

        if (allowances[allowanceId].votes.length >= minVotes) {
            completeAllowanceVote(allowanceId);
        }
    }

    function completeAllowanceVote(uint allowanceId) {
        require(allowances[allowanceId].votes.length >= minVotes);

        allowed[allowances[allowanceId].from][allowances[allowanceId].to] = allowances[allowanceId].allowance;

        CompletedAllowance(allowanceId, allowances[allowanceId].votes);
        Approval(msg.sender, _spender, _value);
    }

    // send a request to the managers to allow other users to withdraw money from your account on your behalf
    function approve(address _spender, uint256 _value) returns (bool success) {
        createAllowanceVote(msg.sender, _spender, _value);
        return true;
    }
}