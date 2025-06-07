// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

import {IERC20} from "./IERC20.sol";

contract Guess {
    
    uint256 MAX_INT = 2**256 - 1;

    address USD_TOKEN_ADDRESS = address(0x216cb9acB601474b2b27ee0BbaFc94c1C7148577);

    uint256 REGISTRATION_USD_GIFT_AMOUNT = 10**9;

    uint256 REGISTRATION_ETH_GIFT_AMOUNT = 5*10**16;

    uint256 MINIMUM_ACCEPTABLE_CONTRACT_ETH_BALANCE = 5*10**17;

    uint256 MINIMUM_ACCEPTABLE_CONTRACT_USD_BALANCE = 10**10;

    address public ownerAddress;

    address public adminAddress;

    address public feeReceiverAddress;
        
    uint256 public nextBetId = 0;

    uint256 public uSDLockedAmount = 0;

    string public  ownerLastMessage = "I will access you from here if needed";
    
    struct UserInformation {
        bool isActive;
        string userName;
        address userAddress;
    }

    struct Bet {
        uint256 id;
        uint256 dueDate;
        string description;
        uint256 outcome;
        bool isActive;
        bool isClosed;
        bool isSettled;
        address closestGuessAddress;
        uint256 baseStakeUnit;
        uint256 feePercentage;
        uint256 collectedAmount;
        uint256 winingAmount;
        uint256 feeAmount;
        uint256 maxSecondsBeforeDueForParticipation;
    }

    struct Prediction  {
        uint256 guess;
        address predictorAddress;
    }

    mapping (uint256 => Bet) public betIdToBet;
    
    mapping(uint256 => Prediction[]) public betIdToPredictions;

    mapping (address => UserInformation) public users;
   

    constructor(){
        address userAddress = msg.sender;
        ownerAddress = userAddress;
        adminAddress= userAddress;
        feeReceiverAddress = userAddress;
    }

    receive() external payable { }

    function changeAdmin(address newAdminAddress) public onlyAdminOrOwner
    {
        require (newAdminAddress != address(0),"empty address");
        adminAddress = newAdminAddress;
    }

    function changeOwner(address newOwnerAddress) public onlyOwner
    {
        require (newOwnerAddress != address(0),"empty address");
        ownerAddress = newOwnerAddress;
    }

    function changeFeeReceiverAddress(address newFeeReceiverAddress) public onlyOwner
    {
        require(newFeeReceiverAddress != address(0),"empty address");
        feeReceiverAddress = newFeeReceiverAddress;
    }

    function notifyUsers( string memory message) public onlyOwner{
        ownerLastMessage = message;
    }

    function cashOutUSD(uint256 cashOutAmount) public onlyOwner {
       uint256 uSDTokenBalance = IERC20(USD_TOKEN_ADDRESS).balanceOf(address(this));
       if((uSDTokenBalance - cashOutAmount)<=uSDLockedAmount){
        return; 
       }
       require(cashOutAmount>0,"zero cashout amount");
       require(IERC20(USD_TOKEN_ADDRESS).transfer(feeReceiverAddress,cashOutAmount),"transfer USD failed");   
    }

    function cashOutEth(uint256 cashOutAmount) public onlyOwner {
        uint256 ethBalance = address(this).balance;
        require(cashOutAmount>0,"zero cashout amount");
        require(ethBalance>cashOutAmount,"not enough ETH balance");
        (bool success, ) = feeReceiverAddress.call{value: cashOutAmount}("");
        require(success,"transfer Ether failed");
    }

    function getContractUSD() public view returns(uint256){
        uint256 uSDTokenBalance = IERC20(USD_TOKEN_ADDRESS).balanceOf(address(this));
        return uSDTokenBalance;
    }
    function getContractETH() public view returns(uint256){
         return address(this).balance;
     }

    function addBet (
        uint256 dueDate, 
        string memory description, 
        uint256 baseStakeUnit, 
        uint256 feePercentage,
        uint256 maxSecondsBeforeDueForParticipation
    )  public onlyAdminOrOwner {
        uint256 betId = nextBetId;
        Bet memory newBet = Bet({
        id:betId,
        dueDate: dueDate,
        description :description,
        outcome: 0,
        isActive:true,
        isClosed:false,
        isSettled: false,
        closestGuessAddress : address(0),
        baseStakeUnit:baseStakeUnit,
        feePercentage:feePercentage,
        collectedAmount : 0,
        winingAmount: 0,
        feeAmount: 0,
        maxSecondsBeforeDueForParticipation: maxSecondsBeforeDueForParticipation
        });
       nextBetId++;
       betIdToBet[betId]=newBet;
    }
    
    function closeBet(uint256 betId, uint256 outcome) public onlyAdminOrOwner {
        Bet memory bet = betIdToBet[betId];
        require (bet.isActive == true);
        uint256 baseStakeUnit = bet.baseStakeUnit;
        Prediction[] memory predictions = betIdToPredictions[betId];
        uint256 closestDistance = MAX_INT;
        address closestGuessAddress = address(0);
        uint256 numberOfPredictions = predictions.length;
        uint256 collectedAmount = 0;
        require(block.timestamp>=bet.dueDate,"Cannot close a bet that is not mature");
        for (uint256 i = 0 ;i<numberOfPredictions;++i)
            {
            uint256 guess = predictions[i].guess;
            collectedAmount = collectedAmount + baseStakeUnit;
            uint256 distance = outcome > guess ? outcome - guess : guess - outcome;
                if (distance<closestDistance){
                    closestGuessAddress=predictions[i].predictorAddress;
                    closestDistance=distance;
                }
            }
        uint256 feeAmount = collectedAmount*bet.feePercentage/100;
        uint256 winingAmount = collectedAmount - feeAmount;
        if(winingAmount<bet.baseStakeUnit) {
            feeAmount = 0;
            winingAmount = collectedAmount;
        }
        uSDLockedAmount = uSDLockedAmount - bet.feeAmount;        
        betIdToBet[betId].closestGuessAddress = closestGuessAddress;
        betIdToBet[betId].collectedAmount = collectedAmount;
        betIdToBet[betId].isClosed = true;
        betIdToBet[betId].outcome = outcome;
        betIdToBet[betId].winingAmount = winingAmount;
        betIdToBet[betId].feeAmount= feeAmount;        
    }

    function betOn(uint256 betId, uint256 guess)public {
        address userAddress = msg.sender;
        Bet memory bet = betIdToBet[betId];
        uint256 requiredUSDTokenAmount = bet.baseStakeUnit; 
        require((bet.dueDate-block.timestamp)>= bet.maxSecondsBeforeDueForParticipation,"Out of time for bet");
        require(users[userAddress].isActive==true,"user not active");
        require(IERC20(USD_TOKEN_ADDRESS).transferFrom(userAddress,address(this), requiredUSDTokenAmount),"USD token is insufficient");    
        require(bet.isActive == true && bet.isClosed == false,"bet is not active or already closed");
        uSDLockedAmount = uSDLockedAmount + bet.baseStakeUnit;
        Prediction memory prediction =  Prediction({guess: guess, predictorAddress : userAddress});
        betIdToPredictions[betId].push(prediction);
    }

    function claimReward(uint256 betId) public {
        address userAddress = msg.sender;
        Bet memory bet = betIdToBet[betId];
        require(bet.isClosed==true,"bet is not closed");
        require(bet.isSettled==false,"bet is already settled");
        require(bet.closestGuessAddress==userAddress);
        IERC20(USD_TOKEN_ADDRESS).transfer(userAddress,bet.winingAmount);
        uSDLockedAmount = uSDLockedAmount - bet.winingAmount;
        if (bet.feeAmount>0){
            IERC20(USD_TOKEN_ADDRESS).transfer(feeReceiverAddress,bet.feeAmount);
        }
        betIdToBet[betId].isSettled = true;
    }

    function register(string memory userName)public returns (UserInformation memory) {
        address userAddress = msg.sender;
        require(users[userAddress].isActive==false,"user already exist");
        if(IERC20(USD_TOKEN_ADDRESS).balanceOf(address(this))>MINIMUM_ACCEPTABLE_CONTRACT_USD_BALANCE+uSDLockedAmount){
            require( IERC20(USD_TOKEN_ADDRESS).transfer(userAddress,REGISTRATION_USD_GIFT_AMOUNT),"USD token transfer failed");
        }
        if(address(this).balance>MINIMUM_ACCEPTABLE_CONTRACT_ETH_BALANCE){
            (bool success,) = userAddress.call{value:REGISTRATION_ETH_GIFT_AMOUNT}("");
            require(success,"Ether transfer failed");
        }
        UserInformation memory newUserInfo = UserInformation(
            {
                isActive : true,
                userName: userName,
                userAddress : userAddress
            }
        );
        users[userAddress] = newUserInfo;
        return newUserInfo;
    }

    function getUserInformation() public view returns(UserInformation memory){
        UserInformation memory userInformation = users[msg.sender];
        return userInformation ;
    } 

    function getBetInformation(uint256 betId) public view returns(Bet memory){
        require (betIdToBet[betId].isActive == true);
         Bet memory bet = betIdToBet[betId];
          return bet;
    }

    function getNextBetId() public  view returns(uint256){
        return nextBetId;
    }

    modifier onlyOwner() {
        require(msg.sender == ownerAddress, "only owner");
        _;
    }

    modifier onlyAdminOrOwner() {
        address userAddress = msg.sender;
        require((userAddress==adminAddress || userAddress == ownerAddress),"only owner or admin");
        _;
    }

}