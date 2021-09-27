// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Staking is Ownable {

    struct Stake {
        uint256 bnbStaked;
        uint256 lastWithdrawnTime;
        uint256 cooldown; 
        uint256 totalCcbEarned;
    }

    struct MembershipLevel {
        uint256 threshold;
        uint256 APY;
    }

    uint256 constant _divider = 1000; //100%
    uint256 public rewardPeriod = 7 days;
    uint256 constant apyBase = 360 days;
    uint256 public rewardMembers;

    mapping(address => Stake) public Stakes;
    MembershipLevel[] public MembershipLevels;
    uint256 public levelsCount = 0;

    IERC20 ccb_token;

    event MembershipAdded(uint256 threshold, uint256 apy, uint256 newLevelsCount);
    event MembershipRemoved(uint256 index, uint256 newLevelsCount);
    event Staked(address fromUser, uint256 bnbAmount,uint256 ccbToken);
    event Claimed(address byUser, uint256 reward);
    event Unstaked(address byUser, uint256 amount);

    constructor(address token) {
        addMembership(0.1 ether, 360); //36%
        addMembership(0.7999 ether, 360); //36%
        addMembership(0.8 ether, 730); //73%  
        addMembership(2 ether, 730); //73%
        setToken(token);
    }

    function changeRewardPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod > 0, "Cannot be 0");
        rewardPeriod = newPeriod;
    }

    // function changeMembershipAPY(uint256 index, uint256 newAPY) external onlyOwner {
    //     require(index <= levelsCount - 1, "Wrong membership id");
    //     if (index > 0) require(MembershipLevels[index - 1].APY < newAPY, "Cannot be lower than previous lvl");
    //     if (index < levelsCount - 1) require(MembershipLevels[index + 1].APY > newAPY, "Cannot be higher than next lvl");
    //     MembershipLevels[index].APY = newAPY;
    // }

    // function changeMembershipThreshold(uint256 index, uint256 newThreshold) external onlyOwner {
    //     require(index <= levelsCount - 1, "Wrong membership id");
    //     if (index > 0) require(MembershipLevels[index - 1].threshold < newThreshold, "Cannot be lower than previous lvl");
    //     if (index < levelsCount - 1) require(MembershipLevels[index + 1].threshold > newThreshold, "Cannot be higher than next lvl");
    //     MembershipLevels[index].threshold = newThreshold;
    // }

    function addMembership(uint256 threshold, uint256 APY) internal {
        require(threshold > 0 && APY > 0, "Threshold and APY should be larger than zero");
        if (levelsCount == 0) {
            MembershipLevels.push(MembershipLevel(threshold, APY));
        } else {
            require(MembershipLevels[levelsCount - 1].threshold < threshold, "New threshold must be larger than the last");
            require(MembershipLevels[levelsCount - 1].APY <= APY, "New APY must be larger than the last");
            MembershipLevels.push(MembershipLevel(threshold, APY));
        }
        levelsCount++;
        emit MembershipAdded(threshold, APY, levelsCount);
    }

    // function removeMembership(uint256 index) external onlyOwner {
    //     require(levelsCount > 0, "Nothing to remove");
    //     require(index <= levelsCount - 1, "Wrong index");

    //     for (uint256 i = index; i < levelsCount - 1; i++) {
    //         MembershipLevels[i] = MembershipLevels[i + 1];
    //     }
    //     delete MembershipLevels[levelsCount - 1];
    //     levelsCount--;
    //     emit MembershipRemoved(index, levelsCount);
    // }

    function setToken(address token) public onlyOwner {
        ccb_token = IERC20(token);
    }

    function getStakeInfo(address user)
        external
        view
        returns (
            uint256 staked,
            uint256 apy,
            uint256 lastClaimed,
            uint256 cooldown
        )
    {
        return (Stakes[user].bnbStaked, getAPY(Stakes[user].bnbStaked), Stakes[user].lastWithdrawnTime, Stakes[user].cooldown);
    }

    function canClaim(address user) public view returns (bool) {
        return (getReward(user) > 0);
    }

    function getAPY(uint256 bnb) public view returns (uint256) {
        require(levelsCount > 0, "No membership levels exist");

        for (uint256 i = levelsCount; i != 0; i--) {
            uint256 currentAPY = MembershipLevels[i - 1].APY;
            uint256 currentThreshold = MembershipLevels[i - 1].threshold;
            if (currentThreshold <= bnb) {
                return currentAPY;
            }
        }
        return 0;
    }

    function calculateReward(
        uint256 APY,
        uint256 cooldown,
        uint256 lastWithdrawn,
        uint256 tokens
    ) public view returns (uint256) {
        if (block.timestamp - cooldown <= lastWithdrawn) return 0;
        return ((block.timestamp - lastWithdrawn) * tokens * APY) / _divider / apyBase;
    }

    function getReward(address user) public view returns (uint256) {
        require(levelsCount > 0, "No membership levels exist");
        if (Stakes[user].bnbStaked == 0) return 0;

        uint256 staked = Stakes[user].bnbStaked;
        uint256 lastWithdrawn = Stakes[user].lastWithdrawnTime;
        uint256 APY = getAPY(staked);
        uint256 cooldown = Stakes[user].cooldown;

        return calculateReward(APY, cooldown, lastWithdrawn, staked);
    }

    function stake() public payable returns (bool) {
        require(msg.value > 0, "Cannot stake 0");
        require(MembershipLevels[0].threshold <= msg.value + Stakes[msg.sender].bnbStaked, "Insufficient tokens for staking.");
        // payable(address(this)).transfer(msg.value);
    

        //if it is the first time then just set lastWithdrawnTime to now
        if (Stakes[msg.sender].bnbStaked == 0) {
            Stakes[msg.sender].cooldown = rewardPeriod;
            Stakes[msg.sender].lastWithdrawnTime = block.timestamp;
            Stakes[msg.sender].totalCcbEarned = 0;
            
            rewardMembers++;
        } else {
            //In case a user has unclaimed TokenX, add them to the newly staked amount
            uint256 reward = getReward(msg.sender);
            if (reward > 0) {
                Stakes[msg.sender].bnbStaked += msg.value;
                Stakes[msg.sender].totalCcbEarned += reward;
                emit Staked(msg.sender, Stakes[msg.sender].bnbStaked,Stakes[msg.sender].totalCcbEarned);
            }
            Stakes[msg.sender].lastWithdrawnTime = block.timestamp;
            Stakes[msg.sender].cooldown = rewardPeriod;

        }

        Stakes[msg.sender].bnbStaked += msg.value;
        emit Staked(msg.sender, msg.value,Stakes[msg.sender].totalCcbEarned);
        return true;
    }

    function claim() external returns (bool) {
        require(canClaim(msg.sender), "Please wait for some time to Claim");
        uint256 reward = getReward(msg.sender);
        ccb_token.transfer(msg.sender, reward);
        Stakes[msg.sender].lastWithdrawnTime = block.timestamp;
        Stakes[msg.sender].cooldown = rewardPeriod;
        Stakes[msg.sender].totalCcbEarned += reward;
        emit Claimed(msg.sender, reward);
        return true;
    }


    function unstake(uint256 unstakeBnbAmount) external returns (bool) {

        require(Stakes[msg.sender].bnbStaked > 0, "Nothing to unstake");
        require(0 < unstakeBnbAmount  && unstakeBnbAmount <= Stakes[msg.sender].bnbStaked, "Unstake amount exceeds total staked amount");
        uint256 reward = getReward(msg.sender);
        if(unstakeBnbAmount == Stakes[msg.sender].bnbStaked){
            payable(msg.sender).transfer(unstakeBnbAmount);
            ccb_token.transfer(msg.sender,reward);
            delete Stakes[msg.sender];
            // Decreases number of total active rewardMembers
            Stakes[msg.sender].totalCcbEarned += reward;
            rewardMembers--;
            emit Claimed(msg.sender, reward);
            emit Unstaked(msg.sender, unstakeBnbAmount);
            return true;
        }else{
            require(Stakes[msg.sender].bnbStaked - unstakeBnbAmount >= MembershipLevels[0].threshold, "The number of tokens you are trying to unstake exceed the required minimum amount. Unstake all tokens or choose a smaller amount");
            payable(msg.sender).transfer(unstakeBnbAmount);
            ccb_token.transfer(msg.sender,reward);
            Stakes[msg.sender].bnbStaked -= unstakeBnbAmount;
            Stakes[msg.sender].lastWithdrawnTime = block.timestamp;
            Stakes[msg.sender].cooldown = rewardPeriod;
            Stakes[msg.sender].totalCcbEarned += reward; 
            emit Claimed(msg.sender, unstakeBnbAmount);
            emit Unstaked(msg.sender, unstakeBnbAmount);
            return true;
        }
    }

    function getUserDetails(address userAddress) public view returns(uint256, uint256, uint256,uint256){
        Stake storage user = Stakes[userAddress];
        uint256 _totalCcbClaimed = user.totalCcbEarned;
        uint256 bnbStaked = user.bnbStaked;
        uint256 liveCcbEarning = _totalCcbClaimed+getReward(userAddress);
        uint256 rewardDate = user.lastWithdrawnTime+user.cooldown;
        return (bnbStaked,_totalCcbClaimed, liveCcbEarning, rewardDate);
    }

    function canClaimAfter(address userAddress) external view returns(uint256){
        Stake storage user = Stakes[userAddress];
        uint256 delta = user.lastWithdrawnTime+user.cooldown;
        if(delta<block.timestamp) return 0;
        return delta-block.timestamp;
    }
    
    
    function adminWithdrawn(uint256 _bnbAmount) external onlyOwner{
        require(msg.sender != address(0),"can not be zero address");
        require(_bnbAmount > 0," withdraw amount can not be zero");
        require(_bnbAmount <= MembershipLevels[0].threshold,"can not withdraw");
        
        payable(owner()).transfer(_bnbAmount);
    }
    
    receive() external payable{
        
    }
    fallback() external payable{
        stake();
    }
}

