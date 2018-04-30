pragma solidity ^0.4.18;
contract CloudSLA {
    
    uint Compensation = 500 finney; ///0.5 ether
    uint ServiceFee = 1 ether;
    uint ServiceDuration = 10 minutes;  
    uint ServiceEnd = 0;
    uint VoteFee = 10 finney;   ///this is the fee for witness to propose its violation
    uint NoViolation4W = 10 finney;  ///the fee for the witness if there is no violation
    uint Violation4W = 100 finney;   ///the fee for the witness in case there is violation
    uint WitnessNumber = 5;
    uint ValidNumber = 4;   ////this is a number to indicate how many witnesses needed to confirm the violation
    uint SharedFee = (WitnessNumber * Violation4W)/2;  ////this is the maximum shared fee to pay the witnesses
    uint ConfirmTimeWin = 2 minutes;   ////the time window for waiting all the witnesses to confirm a violation event 
    uint ConfirmTimeBegin = 0;
    uint ConfirmRepCount = 0;
    
    uint AcceptTimeWin = 2 minutes;   ///the time window for waiting the client to accept this SLA, otherwise the state of SLA is transferred to Completed
    uint AcceptTimeEnd = 0;
  
    enum State { Fresh, Init, Active, Violated, Completed }
    State public SLAState;

    
    //address XClient = 0xd79EBbE4880386f7393adFF0Ac7BdfD6782EBdd2;
    address XClient;
    uint ClientBalance = 0;
    uint CPrepayment = ServiceFee + SharedFee;
    
    //address Provider = 0xCC316266192A89D4ED2B03F5754284e1a205B726;
    address Provider;
    uint ProviderBalance = 0;
    uint PPrepayment = SharedFee;
    
    /////this is the balance to reward the witnesses
    uint SharedBalance = 0;
    
    address[] witnesses = [0x14d3925318f25ed014Eb8c5E4e982fa84224Bcd9, 0x5384aA161C45A61a204c95E82dA1c3fF4Be35005, 0x4c7ae1D70E5F9EdcaCb21fe0B0D4A2e004C1fb6b, 0x7D1577b20af8aE8Ddc8E5B7728883402709170c1, 0x21Bf73BA1A2A507Ba6684a3C6D001cE59Ac22Ca0];
    

    struct Witness {
        bool violated;    ///whether the service agreement is violated
        uint balance;    /// the account balance of this witness
    }
    mapping(address => Witness) witProve;
    
    
    function constuctor()
        public
    {
        Provider = msg.sender;
        SLAState = State.Fresh;
        for(uint i = 0 ; i < witnesses.length ; i++){
            witProve[witnesses[i]].violated = false;
            witProve[witnesses[i]].balance = 0;
        }
    }
    
    modifier checkState(State _state){
        require(SLAState == _state);
        _;
    }
    
    modifier checkProvider() {
        require(msg.sender == Provider);
        _;
    }
    
    modifier checkClient() {
        require(msg.sender == XClient);
        _;
    }
    
    modifier checkMoney(uint _money) {
        require(msg.value == _money);
        _;
    }
    
    ////check whether the sender is a legal witness member 
    modifier checkWitness() {
        
        bool valid = false;
        
        for(uint i = 0 ; i < witnesses.length ; i++){
            if(witnesses[i] == msg.sender){
                    valid = true;
            }
        }
        
        require(valid);
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
    
    //// to ensure all the clients and witnesses has withdrawn money back
    modifier checkAllBalance(){
        require(ClientBalance <= 0);
        
        bool withdrawnAll = true;
        for(uint i = 0 ; i < witnesses.length ; i++){
            if(witProve[witnesses[i]].balance > 0){
                withdrawnAll = false;
                break;
            }
        }
        require(withdrawnAll);
        
        _;
    }
    
    //// this is for Cloud provider to set up this SLA and wait for Client to accept
    function setupSLA(address _client) 
        public 
        payable 
        checkState(State.Fresh) 
        checkProvider
        checkMoney(PPrepayment)
    {
        XClient = _client;
        ProviderBalance = msg.value;
        SLAState = State.Init;
        AcceptTimeEnd = now + AcceptTimeWin;
    }
    
    function cancleSLA()
        public
        checkState(State.Fresh)
        checkProvider
        checkTimeOut(AcceptTimeEnd)
    {
        if(ProviderBalance > 0)
            msg.sender.transfer(ProviderBalance);
        
        ProviderBalance = 0;
    }
    
    //// this is for client to put its prepaid fee and accept the SLA
    function acceptSLA() 
        public 
        payable 
        checkState(State.Init) 
        checkClient
        checkTimeIn(AcceptTimeEnd)
        checkMoney(CPrepayment)
    {
        ClientBalance = msg.value;
        SLAState = State.Active;
        ServiceEnd = now + ServiceDuration;
        
        ///transfer ServiceFee from client to provider 
        ProviderBalance += ServiceFee;
        ClientBalance -= ServiceFee;
        
        ///setup the SharedBalance
        ProviderBalance -= SharedFee;
        ClientBalance -= SharedFee;
        SharedBalance = SharedFee*2;
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
        
        /////cannot vote twice for one witness
        require(witProve[msg.sender].violated == false);
        
        witProve[msg.sender].violated = true;
        witProve[msg.sender].balance = VoteFee;
        
        ConfirmRepCount += 1;
        
        if(ConfirmRepCount >= ValidNumber)
            SLAState = State.Violated;
        else
            equalOp = now;
    }
    
    //// the client end the violated SLA and withdraw its compensation
    function clientEndVSLAandWithdraw()
        public
        checkState(State.Violated) 
        checkTimeOut(ServiceEnd)
        checkClient
    {
        for(uint i = 0 ; i < witnesses.length ; i++){
            if(witProve[witnesses[i]].violated == true){
                witProve[witnesses[i]].balance += Violation4W;  ///reward the witness who report this violation
                SharedBalance -= Violation4W;
            }
        }
        
        ///compensate the client for service violation
        ClientBalance += Compensation;
        ProviderBalance -= Compensation;
        
        /// client and provider divide the remaining shared balance
        if(SharedBalance > 0){
            ClientBalance += (SharedBalance/2);
            ProviderBalance += (SharedBalance/2);
        }
        SharedBalance = 0;
        
        SLAState = State.Completed;
        
        if(ClientBalance > 0)
            msg.sender.transfer(ClientBalance);
        
        ClientBalance = 0;
    }
    
    function clientWithdraw()
        public
        checkState(State.Completed)
        checkTimeOut(ServiceEnd)
        checkClient
    {
        if(ClientBalance > 0)
            msg.sender.transfer(ClientBalance);
            
        ClientBalance = 0;
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
        for(uint i = 0 ; i < witnesses.length ; i++){
            if(witProve[witnesses[i]].violated == true){
                witProve[witnesses[i]].balance = 0;
                SharedBalance += VoteFee;   ////penalty for the reported witness, might be cheating
            }else{
                witProve[witnesses[i]].balance = NoViolation4W;   /// reward the normal witness
                SharedBalance -= NoViolation4W;
            }
        }
        
        /// client and provider divide the remaining shared balance
        if(SharedBalance > 0){
            ClientBalance += (SharedBalance/2);
            ProviderBalance += (SharedBalance/2);
        }
        SharedBalance = 0;
        
        SLAState = State.Completed;
        
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
        if(witProve[msg.sender].balance > 0)
            msg.sender.transfer(witProve[msg.sender].balance);
        
        witProve[msg.sender].balance = 0;
    }
    
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
        for(uint i = 0 ; i < witnesses.length ; i++){
            witProve[witnesses[i]].violated = false;
            witProve[witnesses[i]].balance = 0;
        }
        
        SLAState = State.Fresh;
    }
    
    
    //// this is only for debug in case there is some money stuck in the contract
    function only4Debug()
        public
        checkProvider
    {
        if(address(this).balance > 0)
            msg.sender.transfer(address(this).balance);
    }
    
}