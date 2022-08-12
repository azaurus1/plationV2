// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {InflationFeedInterface} from "./interfaces/IInflationFeed.sol";

contract Prediction is Ownable, Pausable, ReentrancyGuard {
    InflationFeedInterface public oracle;

    bool public genesisLockOnce = false;
    bool public genesisStartOnce = false;

    address public adminAddress; //admin address
    address public operatorAddress; //operator address
    address public keeperAddress; //keeper address

    uint256 public bufferSeconds; // number of seconds for valid execution of a prediction round
    uint256 public intervalSeconds; // interval in seconds between two predictions;

    uint256 public minimumBetAmount; //min bet amount
    uint256 public fee; // fee 200 = 2%
    uint256 public feeAmount; // unclaimed fees

    uint256 public currentEpoch; // current epoch for round

    uint256 public oracleLatestRoundId; // converted from uint80
    uint256 public oracleUpdateAllowance; // seconds

    uint256 public constant MAX_FEE = 1000; // 10% max fee

    mapping(uint256 => mapping(address => Bet)) public betLedger;
    mapping(uint256 => Round) public rounds;
    mapping(address => uint256[]) public userRounds;

    enum Position {
        Over,
        Under
    }

    struct Round {
        uint256 epoch;
        uint256 startTimestamp;
        uint256 lockTimestamp;
        uint256 closeTimestamp;
        int256 lockRate;
        int256 closeRate;
        uint256 lockOracleId;
        uint256 closeOracleId;
        uint256 totalAmount;
        uint256 overAmount;
        uint256 underAmount;
        uint256 rewardBaseCalAmount;
        uint256 rewardAmount;
        bool oracleCalled;
    }

    struct Bet {
        Position position;
        uint256 amount;
        bool claimed; // default should be false
    }

    event BetUnder(address indexed sender, uint256 indexed epoch, uint256 amount);
    event BetOver(address indexed sender, uint256 indexed epoch, uint256 amount);
    event Claim(address indexed sender, uint256 indexed epoch, uint256 amount);
    event EndRound(uint256 indexed epoch, uint256 indexed roundId, int256 price);
    event LockRound(uint256 indexed epoch, uint256 indexed roundId, int256 price);

    event NewAdminAddress(address admin);
    event NewBufferAndIntervalSeconds(uint256 bufferSeconds, uint256 intervalSeconds);
    event NewMinBetAmount(uint256 indexed epoch, uint256 minimumBetAmount);
    event NewFee(uint256 indexed epoch, uint256 fee);
    event NewOperatorAddress(address operator);
    event NewOracle(address oracle);
    event NewOracleUpdateAllowance(uint256 oracleUpdateAllowance);
    event NewKeeperAddress(address keeper);

    event Pause(uint256 indexed epoch);
    event Unpause(uint256 indexed epoch);
    event RewardsCalculated(
        uint256 indexed epoch,
        uint256 rewardBaseCalAmount,
        uint256 rewardAmount,
        uint256 feeAmount
    );

    event StartRound(uint256 indexed epoch);
    event FeeClaim(uint256 amount);

    modifier onlyAdmin(){
        require(msg.sender == adminAddress, "Not admin");
        _;
    }

    modifier onlyAdminOrOperatorOrKeeper(){
        require(
            msg.sender == adminAddress || msg.sender == operatorAddress || msg.sender == keeperAddress,
            "Not operator or admin or keeper"
        );
        _;
    }

    modifier onlyKeeperOrOperator(){
        require(msg.sender == keeperAddress || msg.sender == operatorAddress, "Not keeper or operator");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    constructor(
        address _oracleAddress,
        address _adminAddress,
        address _operatorAddress,
        uint256 _intervalSeconds,
        uint256 _bufferSeconds,
        uint256 _minimumBetAmount,
        uint256 _oracleUpdateAllowance,
        uint256 _fee
    ){
        require(_fee <= MAX_FEE, "Fee is too high!");

        oracle = InflationFeedInterface(_oracleAddress);
        adminAddress = _adminAddress;
        operatorAddress = _operatorAddress;
        intervalSeconds = _intervalSeconds;
        bufferSeconds = _bufferSeconds;
        minimumBetAmount = _minimumBetAmount;
        oracleUpdateAllowance = _oracleUpdateAllowance;
        fee = _fee;

    }

    function betUnder(uint256 epoch) external payable whenNotPaused nonReentrant notContract{
        require(epoch == currentEpoch, "Bet is too early/late");
        require(_bettable(epoch), "Round is not bettable");
        require(msg.value >= minimumBetAmount, "Bet amount must be greater than the minimum bet amount");
        require(betLedger[epoch][msg.sender].amount == 0, "Can only bet once per round");
        
        uint256 amount = msg.value;
        Round storage round = rounds[epoch];
        round.totalAmount = round.totalAmount + amount;
        round.underAmount = round.underAmount + amount;

        Bet storage bet = betLedger[epoch][msg.sender];
        bet.position = Position.Under;
        bet.amount = amount;
        userRounds[msg.sender].push(epoch);

        emit BetUnder(msg.sender, epoch, amount);

    }

    function betOver(uint256 epoch) external payable whenNotPaused nonReentrant {
        require(epoch == currentEpoch, "Bet is too early/late");
        require(_bettable(epoch), "Round is not bettable");
        require(msg.value >= minimumBetAmount, "Bet amount must be greater than the minimum bet amount");
        require(betLedger[epoch][msg.sender].amount == 0, "Can only bet once per round");

        //ADD TRANSFER OF ETH HERE

        uint256 amount = msg.value;
        Round storage round = rounds[epoch];
        round.totalAmount = round.totalAmount + amount;
        round.overAmount = round.overAmount + amount;

        Bet storage bet = betLedger[epoch][msg.sender];
        bet.position = Position.Over;
        bet.amount = amount;
        userRounds[msg.sender].push(epoch);

        emit BetOver(msg.sender, epoch, amount);
    }

    function claim(uint256[] calldata epochs) external nonReentrant notContract {
        uint256 reward; // Initialise reward

        for (uint256 i=0; i < epochs.length; i++){
            require(rounds[epochs[i]].startTimestamp != 0, "Round hasnot started");
            require(block.timestamp > rounds[epochs[i]].closeTimestamp, "Round has not ended");

            uint256 addedReward = 0;

            if (rounds[epochs[i]].oracleCalled){
                require(claimable(epochs[i],msg.sender),"Not eligible for claim");
                Round memory round = rounds[epochs[i]];
                addedReward = (betLedger[epochs[i]][msg.sender].amount * round.rewardAmount) / round.rewardBaseCalAmount;
            }
            else{
                require(refundable(epochs[i],msg.sender),"Not eligible for refund");
                addedReward = betLedger[epochs[i]][msg.sender].amount;
            }

            betLedger[epochs[i]][msg.sender].claimed = true;
            reward += addedReward;

            emit Claim(msg.sender, epochs[i], addedReward);
        }

        if (reward > 0){
            //ADD TRANSFER OF ETH HERE
        }
    }

    function executeRound() external whenNotPaused onlyKeeperOrOperator {
        require(
            genesisStartOnce && genesisLockOnce,
            "Can only run after genesisStartRound and genesisLockRound is triggered"
        );

        (uint80 currentRoundId, int256 currentPrice) = _getRateFromOracle();

        oracleLatestRoundId = uint256(currentRoundId);

        _safeLockRound(currentEpoch, currentRoundId, currentPrice);
        _safeEndRound(currentEpoch - 1, currentRoundId, currentPrice);
        _calculateRewards(currentEpoch - 1);

        currentEpoch = currentEpoch + 1;
        _safeStartRound(currentEpoch);
    }

    function genesisLockRound() external whenNotPaused onlyKeeperOrOperator {
        require(genesisStartOnce, "Can only run after genesisStartRound is triggered");
        require(!genesisLockOnce, "Can only run genesisLockRound once");

        (uint80 currentRoundId, int256 currentPrice) = _getRateFromOracle();

        oracleLatestRoundId = uint256(currentRoundId);

        _safeLockRound(currentEpoch, currentRoundId, currentPrice);

        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch);
        genesisLockOnce = true;
    }

    function genesisStartRound() external whenNotPaused onlyKeeperOrOperator {
        require(!genesisStartOnce, "Can only run genesisStartRound once");

        currentEpoch = currentEpoch + 1;
        _startRound(currentEpoch);
        genesisStartOnce = true;
    }

    function pause() external whenNotPaused onlyAdminOrOperatorOrKeeper {
        _pause();

        emit Pause(currentEpoch);
    }

    function claimFee() external nonReentrant onlyAdmin {
        uint256 currentFeeAmount = feeAmount;
        feeAmount = 0;
        //ADD TRANSFER OF ETH HERE
        emit FeeClaim(currentFeeAmount);
    }

    function unpause() external whenPaused onlyAdminOrOperatorOrKeeper{
        genesisStartOnce = false;
        genesisLockOnce = false;
        _unpause();

        emit Unpause(currentEpoch);
    }

    function setBufferAndIntervalSeconds(uint256 _bufferSeconds, uint256 _intervalSeconds) external whenPaused onlyAdmin{
        require(_bufferSeconds < _intervalSeconds, "bufferSeconds must be less than interval seconds");
        bufferSeconds = _bufferSeconds;
        intervalSeconds = _intervalSeconds;

        emit NewBufferAndIntervalSeconds(_bufferSeconds, _intervalSeconds);
    }

    function setMinimumBetAmount(uint256 _minimumBetAmount) external whenPaused onlyAdmin{
        require(_minimumBetAmount != 0, "Must be greater than 0");
        minimumBetAmount = _minimumBetAmount;

        emit NewMinBetAmount(currentEpoch, minimumBetAmount);
    }

    function setKeeper(address _keeperAddress) external onlyAdmin {
        require(_keeperAddress != address(0), "Cannot be zero address");
        keeperAddress = _keeperAddress;

        emit NewKeeperAddress(_keeperAddress);
    }

    function setOracle(address _oracle) external whenPaused onlyAdmin {
        require(_oracle != address(0), "Cannot be zero address");
        oracleLatestRoundId = 0;
        oracle = InflationFeedInterface(_oracle);

        oracle.latestRoundData();

        emit NewOracle(_oracle);
    }

    function setOracleUpdateAllowance(uint256 _oracleUpdateAllowance) external whenPaused onlyAdmin {
        oracleUpdateAllowance = _oracleUpdateAllowance;

        emit NewOracleUpdateAllowance(_oracleUpdateAllowance);
    }

    function setFee(uint256 _fee) external whenPaused onlyAdmin {
        require(_fee <= MAX_FEE, "Fee is too high");
        fee = _fee;

        emit NewFee(currentEpoch, fee);
    }

    function setAdmin(address _adminAddress) external onlyOwner {
        require(_adminAddress != address(0), "Cannot be zero address");
        adminAddress = _adminAddress;

        emit NewAdminAddress(_adminAddress);
    }

    function getUserRounds(
        address user,
        uint256 cursor,
        uint256 size
    )
    external
    view
    returns (
        uint256[] memory,
        Bet[] memory,
        uint256
    )
    {
        uint256 length = size;

        if (length > userRounds[user].length - cursor){
            length = userRounds[user].length - cursor;
        }

        uint256[] memory values = new uint256[](length);
        Bet[] memory bet = new Bet[](length);

        for (uint256 i=0; i < length; i++){
            values[i] = userRounds[user][cursor + i];
            bet[i] = betLedger[values[i]][user];
        }

        return (values, bet, cursor + length);
    }

    function getUserRoundsLength(address user) external view returns (uint256) {
        return userRounds[user].length;
    }

    function claimable(uint256 epoch, address user) public view returns (bool) {
        Bet memory bet = betLedger[epoch][user];
        Round memory round = rounds[epoch];
        if (round.lockRate == round.closeRate){
            return false;
        }
        return
            round.oracleCalled &&
            bet.amount != 0 &&
            !bet.claimed &&
            ((round.closeRate > round.lockRate && bet.position == Position.Over) || 
                (round.closeRate < round.lockRate && bet.position == Position.Under));
    }

    function refundable(uint256 epoch, address user) public view returns (bool) {
        Bet memory bet = betLedger[epoch][user];
        Round memory round = rounds[epoch];
        return
            !round.oracleCalled &&
            !bet.claimed &&
            block.timestamp > round.closeTimestamp + bufferSeconds &&
            bet.amount != 0;
    }

    function _calculateRewards(uint256 epoch) internal {
        require(rounds[epoch].rewardBaseCalAmount == 0 && rounds[epoch].rewardAmount == 0, "Rewards calculated");
        Round storage round = rounds[epoch];
        uint256 rewardBaseCalAmount;
        uint256 feeAmt;
        uint256 rewardAmount;

        if (round.closeRate > round.lockRate) {
            rewardBaseCalAmount = round.overAmount;
            
            if (rewardBaseCalAmount == 0) {
                feeAmt = round.totalAmount;
            }else{
                feeAmt = (round.totalAmount * fee) / 10000;
            }
            rewardAmount = round.totalAmount - feeAmt;
        }

        else if (round.closeRate < round.lockRate) {
            rewardBaseCalAmount = round.underAmount;

            if (rewardBaseCalAmount == 0){
                feeAmt = round.totalAmount;
            }else{
                feeAmt = (round.totalAmount * fee) / 10000;
            }
            rewardAmount = round.totalAmount - feeAmt;
        }
        else {
            rewardBaseCalAmount = 0;
            rewardAmount = 0;
            feeAmt = round.totalAmount;
        }
        round.rewardBaseCalAmount = rewardBaseCalAmount;
        round.rewardAmount = rewardAmount;

        feeAmount += feeAmt;

        emit RewardsCalculated(epoch, rewardBaseCalAmount, rewardAmount, feeAmount);
    }

    function _safeEndRound(
        uint256 epoch,
        uint256 roundId,
        int256 price
    ) internal {
        require(rounds[epoch].lockTimestamp != 0, "Can only end round after round has locked");
        require(block.timestamp >= rounds[epoch].closeTimestamp, "Can only end round after closeTimestamp");
        require (
            block.timestamp <= rounds[epoch].closeTimestamp + bufferSeconds,
            "Can only end round within bufferSeconds"
        );
        Round storage round = rounds[epoch];
        round.closeRate = price;
        round.closeOracleId = roundId;
        round.oracleCalled= true;

        emit EndRound(epoch, roundId, round.closeRate);
    }

    function _safeLockRound(
        uint256 epoch,
        uint256 roundId,
        int256 price
    ) internal {
        require(rounds[epoch].startTimestamp != 0, "Can only lock round after round has started");
        require(block.timestamp >= rounds[epoch].lockTimestamp, "Can only lock round after lockTimestamp");
        require(
            block.timestamp <= rounds[epoch].lockTimestamp + bufferSeconds,
            "Can only lock round within bufferSeconds"
        );
        Round storage round = rounds[epoch];
        round.closeTimestamp = block.timestamp + intervalSeconds;
        round.lockRate = price;
        round.lockOracleId = roundId;

        emit LockRound(epoch, roundId, round.lockRate);
    }

    function _safeStartRound(uint256 epoch) internal {
        require(genesisStartOnce, "Can only run after genesisStartRound is triggered");
        require(rounds[epoch - 2].closeTimestamp != 0,"Can only start round after round n-2 has ended");
        require(
            block.timestamp >= rounds[epoch - 2].closeTimestamp,
            "Can only start new round after round n-2 closeTimestamp"
        );
        _startRound(epoch);
    }

    function _startRound(uint256 epoch) internal {
        Round storage round = rounds[epoch];
        round.startTimestamp = block.timestamp;
        round.lockTimestamp = block.timestamp + intervalSeconds;
        round.closeTimestamp = block.timestamp + (2 * intervalSeconds);
        round.epoch = epoch;
        round.totalAmount = 0;

        emit StartRound(epoch);
    }

    function _bettable(uint256 epoch) internal view returns (bool){
        return
            rounds[epoch].startTimestamp != 0 &&
            rounds[epoch].lockTimestamp != 0 &&
            block.timestamp > rounds[epoch].startTimestamp &&
            block.timestamp < rounds[epoch].lockTimestamp;
    }

    function _getRateFromOracle() internal view returns (uint80, int256) {
        uint256 leastAllowedTimestamp = block.timestamp + oracleUpdateAllowance;
        (uint80 roundId, int256 rate, uint256 timestamp)= oracle.latestRoundData();
        require(timestamp <= leastAllowedTimestamp, "Oracle update exceeded max timestamp allowance");
        require(
            uint256(roundId) > oracleLatestRoundId,
            "Oracle update roundId must be larger than oracleLatestRoundId"
        );
        return (roundId, rate);
    }

    function _isContract(address account) internal view returns (bool){
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}