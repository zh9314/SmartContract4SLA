pragma solidity ^0.4.18;

contract WitnessPool {
    
    uint public onlineCounter = 0;
    
    enum WState { Offline, Online, Candidate, Busy }
    
    struct Witness {
        bool registered;    ///true: this witness has registered.
        uint index;         ///the index of the witness in the address pool, if it is registered
        
        WState state;    ///the state of the witness
        
        address SLAContract;    ////the contract address of 
        uint confirmDeadline;   ////Must confirm the sortition in the state of Candidate. Otherwise, reputation -10.
        int8 reputation;       ///the reputation of the witness, the initial value is 100. If it is 0, than it is blocked.
    }

    mapping(address => Witness) witnessPool;    
    address [] public witnessAddrs;    ////the address pool of witnesses

    
    struct SortitionInfo{
        bool valid;
        uint curBlockNum;
        uint8 blkNeed;   ////how many blocks needed for sortition
    }
    mapping(address => SortitionInfo) SLAContractPool;   ////record the requester's initial block number. The sortition will be based on the hash value after this block.
    
    
    ////record the provider _who generates a SLA contract of address _contractAddr at time _time
    event SLAContractGen(address indexed _who, uint _time, address _contractAddr);
    
    event WitnessSelected(address indexed _who, uint _index, address _forWhom);
    
    ////check whether the register has already registered
    modifier checkRegister(address _register){
        require(!witnessPool[_register].registered);
        _;
    }
    
    ////check whether it is a registered witness
    modifier checkWitness(address _witness){
        require(witnessPool[_witness].registered);
        _;
    }
    
    ////check whether it is a valid SLA contract
    modifier checkSLAContract(address _sla){
        require(SLAContractPool[_sla].valid);
        _;
    }
    
    /**
     * Provider Interface::
     * This is for the provider to generate a SLA contract
     * */
    function genSLAContract() 
        public 
        returns
        (address)
    {
        address newSLAContract = new CloudSLA(this, msg.sender, 0x0);
        SLAContractPool[newSLAContract].valid = true; 
        emit SLAContractGen(msg.sender, now, newSLAContract);
        return newSLAContract;
    }
    
    /**
     * Normal User Interface::
     * Check whether a SLAContract address is valid
     * */
    function validateSLA(address _SLAContract) 
        public
        view
        returns
        (bool)
    {
        if(SLAContractPool[_SLAContract].valid)
            return true;
        else
            return false;
    }
    
    /**
     * Normal User Interface::
     * This is for the normal user to register as a witness into the pool
     * */
    function register() 
        public 
        checkRegister(msg.sender) 
    {
        witnessPool[msg.sender].index = witnessAddrs.push(msg.sender) - 1;
        witnessPool[msg.sender].state = WState.Offline;
        witnessPool[msg.sender].reputation = 100; 
        witnessPool[msg.sender].registered = true;
    }
    
    
    
    /**
     * Contract Interface::
     * This is for SLA contract to submit a committee sortition request.
     * _blkNeed: This is a number to specify how many blocks needed in the future for the committee sortition. 
     *            Its range should be 2~255. The recommended value is 12.  
     * */
    function request(uint8 _blkNeed)
        public 
        checkSLAContract(msg.sender)
        returns
        (bool success)
    {
        ////record current block number
        SLAContractPool[msg.sender].curBlockNum = block.number;
        SLAContractPool[msg.sender].blkNeed = _blkNeed;
        return true;
    }
    
    /**
     * Contract Interface::
     * Request for a sortition of _N witnesses. The _provider and _customer must not be selected.
     * */
    function sortition(uint _N, address _provider, address _customer)
        public
        checkSLAContract(msg.sender)
        returns
        (bool success)
    {
        //// there should be more than 10 times of _N online witnesses
        require(onlineCounter > _N);   ///this is debug mode
        //require(onlineCounter > 10*_N);
        
        
        //// there should be more than extra 2*blkNeed blocks generated  
        require( block.number > SLAContractPool[msg.sender].curBlockNum + 2*SLAContractPool[msg.sender].blkNeed );
        uint seed = 0;
        for(uint bi = 0 ; bi<SLAContractPool[msg.sender].blkNeed ; bi++)
            seed += (uint)(block.blockhash( SLAContractPool[msg.sender].curBlockNum + bi + 1 ));
        
        uint wcounter = 0;
        while(wcounter < _N){
            address sAddr = witnessAddrs[seed % witnessAddrs.length];
            
            if(witnessPool[sAddr].state == WState.Online && witnessPool[sAddr].reputation > 0
               && sAddr != _provider && sAddr != _customer)
            {
                witnessPool[sAddr].state = WState.Candidate;
                witnessPool[sAddr].confirmDeadline = now + 5 minutes;   /// 5 minutes for confirmation
                witnessPool[sAddr].SLAContract = msg.sender;
                emit WitnessSelected(sAddr, witnessPool[sAddr].index, msg.sender);
                onlineCounter--;
                wcounter++;
            }
            
            seed = (uint)(keccak256(uint(seed)));
        }
        return true;
    }
    
    /**
     * Contract Interface::
     * Candidate witness calls the SLA contract and confirm the sortition. 
     * */
    function confirm(address _candidate)
        public
        checkWitness(_candidate)
        checkSLAContract(msg.sender)
        returns 
        (bool)
    {
        ////have not reached the confirmation deadline
        require( now < witnessPool[_candidate].confirmDeadline );
        
        ////only able to confirm in candidate state
        require(witnessPool[_candidate].state == WState.Candidate);
        
        ////only the SLA contract can select it.
        require(witnessPool[_candidate].SLAContract == msg.sender);
        
        witnessPool[_candidate].state = WState.Busy;
        
        return true;
    }
    
    /**
     * Contract Interface::
     * SLA contract ends and witness calls this from the contract to release the Busy witness. 
     * */
    function release(address _witness)
        public
        checkWitness(_witness)
        checkSLAContract(msg.sender)
    {
        ////only able to release in Busy state
        require(witnessPool[_witness].state == WState.Busy);
        
        ////only the SLA contract can operate on it.
        require(witnessPool[_witness].SLAContract == msg.sender);
        
        witnessPool[_witness].state = WState.Online;
        onlineCounter++;
        
    }
    
    
    
    /**
     * Witness Interface::
     * Reject the sortition for candidate. Because the SLA contract is not valid.
     * */
    function reject()
        public
        checkWitness(msg.sender)
    {
        ////only reject in candidate state
        require(witnessPool[msg.sender].state == WState.Candidate);
        
        ////have not reached the rejection deadline
        require( now < witnessPool[msg.sender].confirmDeadline );
        
        witnessPool[msg.sender].state = WState.Online;
        onlineCounter++;
    }
    
    /**
     * Witness Interface::
     * Reverse its own state to Online after the confirmation deadline. But need to reduece the reputation. 
     * */
    function reverse()
        public
        checkWitness(msg.sender)
    {
        ////must exceed the confirmation deadline
        require( now > witnessPool[msg.sender].confirmDeadline );
        
        ////able to turn only in candidate state
        require(witnessPool[msg.sender].state == WState.Candidate);
        
        witnessPool[msg.sender].state = WState.Online;
        onlineCounter++;
        
        witnessPool[msg.sender].reputation -= 10;
    }
    
    /**
     * Witness Interface::
     * Turn online to wait for sortition.
     * */
    function turnOn()
        public
        checkWitness(msg.sender)
    {
        
        ////must be in the state of offline
        require(witnessPool[msg.sender].state == WState.Offline);
        
        witnessPool[msg.sender].state = WState.Online;
        onlineCounter++;
    }
    
    /**
     * Witness Interface::
     * Turn offline to avoid sortition.
     * */
    function turnOff()
        public
        checkWitness(msg.sender)
    {
        
        ////must be in the state of online
        require(witnessPool[msg.sender].state == WState.Online);
        
        witnessPool[msg.sender].state = WState.Offline;
        onlineCounter--;
    }
    
    
    /**
     * Witness Interface::
     * For witness itself to check the state of itself.
     * */
    function checkWState(address _witness)
        public
        view
        returns
        (WitnessPool.WState, uint)
    {
        return (witnessPool[_witness].state, witnessPool[_witness].confirmDeadline);
    }
    
}


contract CloudSLA {
    
    enum State { Fresh, Init, Active, Violated, Completed }
    State public SLAState;
    
    WitnessPool public wp;
    
    string public cloudServiceDetail = "";
    
    uint8 public BlkNeeded = 2;
    
    uint public CompensationFee = 500 finney; ///0.5 ether
    uint public ServiceFee = 1 ether;
    uint public ServiceDuration = 10 minutes;  
    uint ServiceEnd = 0;
    
    uint public WF4NoViolation = 10 finney;  ///the fee for the witness if there is no violation
    uint WF4Violation = 10*WF4NoViolation;   ///the fee for the witness in case there is violation
    uint VoteFee = WF4NoViolation;   ///this is the fee for witness to report its violation
    
    uint public WitnessNumber = 3;   ///N
    uint public ConfirmNumber = 2;   ////M: This is a number to indicate how many witnesses needed to confirm the violation
    
    uint SharedFee = (WitnessNumber * WF4Violation)/2;  ////this is the maximum shared fee to pay the witnesses
    uint ConfirmTimeWin = 2 minutes;   ////the time window for waiting all the witnesses to confirm a violation event 
    uint ConfirmTimeBegin = 0;
    uint ConfirmRepCount = 0;
    
    uint AcceptTimeWin = 2 minutes;   ///the time window for waiting the customer to accept this SLA, otherwise the state of SLA is transferred to Completed
    uint AcceptTimeEnd = 0;

    address public Customer;
    uint CustomerBalance = 0;
    uint CPrepayment = ServiceFee + SharedFee;
    
    address public Provider;
    uint ProviderBalance = 0;
    uint PPrepayment = SharedFee;
    
    /////this is the balance to reward the witnesses from the committee
    uint SharedBalance = 0;
    
    //// this is the witness committee
    address [] public witnessCommittee;
    

    struct WitnessAccount {
        bool selected;   ///wheterh it is a member witness committee
        bool violated;   ///whether it has reported that the service agreement is violated 
        uint balance;    ///the account balance of this witness
    }
    mapping(address => WitnessAccount) witnesses;
    
    ////this is to log event that _who modified the SLA state to _newstate at time stamp _time
    event SLAStateModified(address indexed _who, uint _time, State _newstate);
    
    ////this is to log event that _witness report a violation at time stamp _time for a SLA monitoring round of _roundID
    event SLAViolationRep(address indexed _witness, uint _time, uint _roundID);
    
    
    function CloudSLA(WitnessPool _witnessPool, address _provider, address _customer)
        public
    {
        Provider = _provider;
        Customer = _customer;
        wp = _witnessPool;
    }
    
    ///following functinos are used for setting parameters instead of default ones
    
    
    modifier checkState(State _state){
        require(SLAState == _state);
        _;
    }
    
    modifier checkProvider() {
        require(msg.sender == Provider);
        _;
    }
    
    modifier checkCustomer() {
        require(msg.sender == Customer);
        _;
    }
    
    modifier checkMoney(uint _money) {
        require(msg.value == _money);
        _;
    }
    
    ////check whether the sender is a legal witness member in the committee 
    modifier checkWitness() {
        
        require(witnesses[msg.sender].selected);
        _;
    }
    
    modifier checkTimeIn(uint _endTime) {
        require(now < _endTime);
        _;
    }
    
    modifier checkTimeOut(uint _endTime) {
        require(now > _endTime);
        _;
    }
    
    //// to ensure all the customers and witnesses has withdrawn money back
    modifier checkAllBalance(){
        require(CustomerBalance == 0);
        
        bool withdrawnAll = true;
        for(uint i = 0 ; i < witnessCommittee.length ; i++){
            if(witnesses[witnessCommittee[i]].balance > 0){
                withdrawnAll = false;
                break;
            }
        }
        
        require(withdrawnAll);
        
        _;
    }
    
    function setBlkNeeded(uint8 _blkNeed)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        require(_blkNeed > 1);
        BlkNeeded = _blkNeed;
    }
    
    ////the unit is Szabo = 0.001 finney
    function setCompensationFee(uint _cs)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        require(_cs > 0);
        uint oneUnit = 1 szabo;
        CompensationFee = _cs*oneUnit;
    }
    
    function setServiceFee(uint _ss)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        require(_ss > 0);
        uint oneUnit = 1 szabo;
        ServiceFee = _ss*oneUnit;
    }
    
    function setWitnessFee(uint _ws)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        require(_ws > 0);
        uint oneUnit = 1 szabo;
        WF4NoViolation = _ws*oneUnit;
    }
    
    //the unit is minutes
    function setServiceDuration(uint _sd)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        require(_sd > 0);
        uint oneUnit = 1 minutes;
        ServiceDuration = _sd*oneUnit;
    }
    
    //Set the witness committee number, which is the 'N'
    function setWitnessCommNum(uint _wn)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        require(_wn > 2);
        WitnessNumber = _wn;
    }
    
    //Set the 'M' out of 'N' to confirm the violation
    function setConfirmNum(uint _m)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        //// N/2 < M < N 
        require(_m > (WitnessNumber/2));
        require(_m < WitnessNumber);
        
        ConfirmNumber = _m;
    }
    
    //Set the customer address
    function setCustomer(address _customer)
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        Customer = _customer;
    }
    
     //// this is for Cloud provider to publish its service detail
    function publishService(string _detail) 
        public 
        checkState(State.Fresh) 
        checkProvider
    {
        cloudServiceDetail = _detail;
    }
    
    //// this is for Cloud provider to set up this SLA and wait for Customer to accept
    function setupSLA() 
        public 
        payable 
        checkState(State.Fresh) 
        checkProvider
        checkMoney(PPrepayment)
    {
        require(WitnessNumber == witnessCommittee.length);
        
        ProviderBalance = msg.value;
        SLAState = State.Init;
        AcceptTimeEnd = now + AcceptTimeWin;
        emit SLAStateModified(msg.sender, now, State.Init);
    }
    
    function cancleSLA()
        public
        checkState(State.Init)
        checkProvider
        checkTimeOut(AcceptTimeEnd)
    {
        if(ProviderBalance > 0)
            msg.sender.transfer(ProviderBalance);
        
        SLAState = State.Fresh;
        ProviderBalance = 0;
    }
    
    //// this is for customer to put its prepaid fee and accept the SLA
    function acceptSLA() 
        public 
        payable 
        checkState(State.Init) 
        checkCustomer
        checkTimeIn(AcceptTimeEnd)
        checkMoney(CPrepayment)
    {
        require(WitnessNumber == witnessCommittee.length);
        
        CustomerBalance = msg.value;
        SLAState = State.Active;
        emit SLAStateModified(msg.sender, now, State.Active);
        ServiceEnd = now + ServiceDuration;
        
        ///transfer ServiceFee from customer to provider 
        ProviderBalance += ServiceFee;
        CustomerBalance -= ServiceFee;
        
        ///setup the SharedBalance
        ProviderBalance -= SharedFee;
        CustomerBalance -= SharedFee;
        SharedBalance = SharedFee*2;
    }
    
    /**
     * Customer Interface:
     * Reset the witnesses' state, who have reported.
     * */
    function resetWitness() 
        public 
        checkState(State.Active) 
        checkCustomer
        checkTimeIn(ServiceEnd)
    {
        ////some witness has reported the violation
        require(ConfirmTimeBegin != 0);
        
        ////some witness reported, but the violation is not confirmed 
        require(now > ConfirmTimeBegin + ConfirmTimeWin);
        
        ConfirmRepCount = 0;
        ConfirmTimeBegin = 0;
        for(uint i = 0 ; i < witnessCommittee.length ; i++){
            if(witnesses[witnessCommittee[i]].violated == true){
                witnesses[witnessCommittee[i]].violated = false;
                SharedBalance += witnesses[witnessCommittee[i]].balance;    ///penalty
                witnesses[witnessCommittee[i]].balance = 0;
            }
        }
        
    }
    
    
    function reportViolation()
        public
        payable
        checkState(State.Active) 
        checkTimeIn(ServiceEnd)
        checkWitness
        checkMoney(VoteFee)
    {
        uint equalOp = 0;   /////nonsense operation to make every one using the same gas 
        
        if(ConfirmTimeBegin == 0)
            ConfirmTimeBegin = now;
        else
            equalOp = now;    
        
        ////only valid within the confirmation time window
        require(now < ConfirmTimeBegin + ConfirmTimeWin);
        
        /////one witness cannot vote twice 
        require(witnesses[msg.sender].violated == false);
        
        witnesses[msg.sender].violated = true;
        witnesses[msg.sender].balance = VoteFee;
        
        ConfirmRepCount += 1;
        
        if(ConfirmRepCount >= ConfirmNumber){
            SLAState = State.Violated;
            emit SLAStateModified(msg.sender, now, State.Violated);
        }
        else{
            equalOp = now;
            equalOp = now;
        }
        
        emit SLAViolationRep(msg.sender, now, ServiceEnd);
    }
    
    //// the customer end the violated SLA and withdraw its compensation
    function customerEndVSLAandWithdraw()
        public
        checkState(State.Violated) 
        checkTimeOut(ServiceEnd)
        checkCustomer
    {
        for(uint i = 0 ; i < witnessCommittee.length ; i++){
            if(witnesses[witnessCommittee[i]].violated == true){
                witnesses[witnessCommittee[i]].balance += WF4Violation;  ///reward the witness who report this violation
                SharedBalance -= WF4Violation;
            }
        }
        
        ///compensate the customer for service violation
        CustomerBalance += CompensationFee;
        ProviderBalance -= CompensationFee;
        
        /// customer and provider divide the remaining shared balance
        if(SharedBalance > 0){
            CustomerBalance += (SharedBalance/2);
            ProviderBalance += (SharedBalance/2);
        }
        SharedBalance = 0;
        
        SLAState = State.Completed;
        emit SLAStateModified(msg.sender, now, State.Completed);
        
        if(CustomerBalance > 0)
            msg.sender.transfer(CustomerBalance);
        
        CustomerBalance = 0;
    }
    
    function customerWithdraw()
        public
        checkState(State.Completed)
        checkTimeOut(ServiceEnd)
        checkCustomer
    {
        if(CustomerBalance > 0)
            msg.sender.transfer(CustomerBalance);
            
        CustomerBalance = 0;
    }
    
    function providerWithdraw()
        public
        checkState(State.Completed)
        checkTimeOut(ServiceEnd)
        checkProvider
    {
        if(ProviderBalance > 0)
            msg.sender.transfer(ProviderBalance);
        
        ProviderBalance = 0;
    }
    
    
    //// this means there is no violation during this service. This function needs provider to invoke to end and gain its benefit
    function providerEndNSLAandWithdraw()
        public
        checkState(State.Active)
        checkTimeOut(ServiceEnd)
        checkProvider
    {
        for(uint i = 0 ; i < witnessCommittee.length ; i++){
            if(witnesses[witnessCommittee[i]].violated == true){
                witnesses[witnessCommittee[i]].balance = 0;
                SharedBalance += VoteFee;   ////penalty for the reported witness, might be cheating
            }else{
                witnesses[witnessCommittee[i]].balance = WF4NoViolation;   /// reward the normal witness
                SharedBalance -= WF4NoViolation;
            }
        }
        
        /// customer and provider divide the remaining shared balance
        if(SharedBalance > 0){
            CustomerBalance += (SharedBalance/2);
            ProviderBalance += (SharedBalance/2);
        }
        SharedBalance = 0;
        
        SLAState = State.Completed;
        emit SLAStateModified(msg.sender, now, State.Completed);
        
        if(ProviderBalance > 0)
            msg.sender.transfer(ProviderBalance);
            
        ProviderBalance = 0;
    }
    
    function witnessWithdraw()
        public
        checkState(State.Completed)
        checkTimeOut(ServiceEnd)
        checkWitness
    {
        require(witnesses[msg.sender].balance > 0);
            
        msg.sender.transfer(witnesses[msg.sender].balance);
        
        witnesses[msg.sender].balance = 0;
        
        
    }
    
    ///this only restart the SLA lifecycle, not including the selecting the witness committee. This is to continuously deliver the servce. 
    function restartSLA()
        public
        payable
        checkState(State.Completed)
        checkTimeOut(ServiceEnd)
        checkProvider
        checkAllBalance
        checkMoney(PPrepayment)
    {
        require(WitnessNumber == witnessCommittee.length);
        
        //// in case there are some unexpected errors happen, provider can withdraw all the money back anyway
        if(address(this).balance > 0)
            msg.sender.transfer(address(this).balance);
        
        /// reset all the related values
        ConfirmRepCount = 0;
        ConfirmTimeBegin = 0;
        
        ///reset the witnesses' state only
        for(uint i = 0 ; i < witnessCommittee.length ; i++){
            if(witnesses[witnessCommittee[i]].violated == true)
                witnesses[witnessCommittee[i]].violated = false;
        }
        
        
        ProviderBalance = msg.value;
        SLAState = State.Init;
        AcceptTimeEnd = now + AcceptTimeWin;
        emit SLAStateModified(msg.sender, now, State.Init);
    }
    
    ////this is to flush all the witnesses in the committee. Go back to Fresh state.
    function resetSLA()
        public
        checkState(State.Completed)
        checkTimeOut(ServiceEnd)
        checkProvider
        checkAllBalance
    {
        //// in case there are some unexpected errors happen, provider can withdraw all the money back anyway
        if(address(this).balance > 0)
            msg.sender.transfer(address(this).balance);
        
        /// reset all the related values
        ConfirmRepCount = 0;
        ConfirmTimeBegin = 0;
        
        ///reset the witness committee
        for(uint i = 0 ; i < witnessCommittee.length ; i++)
            delete witnesses[witnessCommittee[i]];
        
        delete witnessCommittee;
        
        SLAState = State.Fresh;
        emit SLAStateModified(msg.sender, now, State.Fresh);
    }
    
    
    //// this is only for debug in case there is some money stuck in the contract
    /*
    function only4DebugWithdraw()
        public
        checkProvider
    {
        if(address(this).balance > 0)
            msg.sender.transfer(address(this).balance);
    }
    
    
    function only4DebugChangeState(State _newstate)
        public
        checkProvider
    {
        SLAState = _newstate;
    }
    */
    
    
    function requestSotition()
        public
        checkProvider
        returns
        (bool success)
    {
        require(wp.request(BlkNeeded));
        return true;
    }
    
    function sotitionFromWP(uint _N)
        public
        checkProvider
        returns
        (bool success)
    {
        
        require(WitnessNumber > witnessCommittee.length);
        
        require(WitnessNumber - witnessCommittee.length >= _N);
        
        require(Customer != 0x0);
        
        require(wp.sortition(_N, Provider, Customer));
        return true;
    }
    
    function getCommitteeCount()
        public
        view
        returns
        (uint)
    {
        return witnessCommittee.length; 
    }
    
    ///the candidate witness confirm itself
    function witnessConfirm()
        public
        returns
        (bool)
    {
        ////have not registered in the witness committee
        require(!witnesses[msg.sender].selected);
        
        ////The candidate witness can neither be the provider nor the customer
        require(msg.sender != Provider);
        require(msg.sender != Customer);
        
        ///confirm with the witness pool
        require(wp.confirm(msg.sender));
        witnessCommittee.push(msg.sender);
        witnesses[msg.sender].selected = true;
        
        return true;
    }
    
    ///the witness has the right to leave the SLA contract in following scenarios
    ///1. As long as not in the state of 'Active' or 'Violated'
    ///2. If it is the state of 'Init', the time should be out of the 'AcceptTimeEnd'
    function witnessRelease()
        public
        checkWitness
    {
        ////not in the 'Active', 'Violated' or 'Completed' state
        require(SLAState != State.Active);
        require(SLAState != State.Violated);
        
        require(SLAState == State.Init && now > AcceptTimeEnd);
        
        
        uint index = witnessCommittee.length;
        for(uint i = 0 ; i<witnessCommittee.length ; i++){
            if(witnessCommittee[i] == msg.sender)
                index = i;
        }
        require(index != witnessCommittee.length);
        ////move the last one in the list to replace the deleted one
        witnessCommittee[index] = witnessCommittee[witnessCommittee.length - 1];
            
        witnessCommittee.length--;
            
        delete witnesses[msg.sender];
            
        wp.release(msg.sender);
        
    }
    
}