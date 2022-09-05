// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "../Prediction.sol";
import "../test-helpers/InflationFeedHelper.sol";
import {console} from "forge-std/console.sol";


contract PredictionTest is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    InflationFeedHelper public inflationFeedHelper;
    Prediction public prediction;
    address public oracleAddress;
    address public operatorAddress = 0x37398D31E42060d805DA39D9b4Ff4290a0fbbc03;
    uint256 public intervalSeconds = 86400;
    uint256 public bufferSeconds = 30;
    uint256 public minimumBetAmount = 100000000000000;
    uint256 public oracleUpdateAllowance = 30;
    uint256 public fee = 300;

    address internal betsOver = 0x39D934B4A4561684C198Ab585f872433E552d045;
    address internal betsUnder = 0x878A672d4B1dA44fBE2dC6d040dA7Acc19EFa7A6;
    
    uint256[] public tempEpoch = new uint256[](1);
    uint256 public temp = 3;


    function setUp() public {
        tempEpoch[0] = temp;
        inflationFeedHelper = new InflationFeedHelper();
        prediction = new Prediction(address(inflationFeedHelper),msg.sender,operatorAddress,intervalSeconds,bufferSeconds,minimumBetAmount,oracleUpdateAllowance,fee);
    }

    function testOracleAddress() public{
        assertEq(address(prediction.oracle()),address(inflationFeedHelper));
    }
    function testOperatorAddress() public{
        assertEq(address(prediction.operatorAddress()), operatorAddress);
    }
    function testIntervalSeconds() public{
        assertEq(prediction.intervalSeconds(),intervalSeconds);
    }
    function testBufferSeconds() public{
        assertEq(prediction.bufferSeconds(),bufferSeconds);
    }
    function testMinimumBet() public{
        assertEq(prediction.minimumBetAmount(),minimumBetAmount);
    }
    function testOracleUpdateAllowance() public{
        assertEq(prediction.oracleUpdateAllowance(),oracleUpdateAllowance);
    }
    function testFee() public{
        assertEq(prediction.fee(),fee);
    }
    function testSetBufferInterval(uint256 _amount1, uint256 _amount2) public{
        vm.startPrank(prediction.adminAddress());
        prediction.pause();
        vm.assume(_amount1 < _amount2);
        prediction.setBufferAndIntervalSeconds(_amount1, _amount2);
        vm.stopPrank();
        assertEq(prediction.bufferSeconds(), _amount1);
        assertEq(prediction.intervalSeconds(), _amount2);
    }
    function testSetMinimumBet(uint256 _amount) public{
        vm.startPrank(prediction.adminAddress());
        prediction.pause();
        vm.assume(0 < _amount);
        prediction.setMinimumBetAmount(_amount);
        vm.stopPrank();
        assertEq(prediction.minimumBetAmount(), _amount);
    }
    function testSetKeeper(address _address) public{
        vm.startPrank(prediction.adminAddress());
        vm.assume(_address != address(0));
        prediction.pause();
        prediction.setKeeper(_address);
        vm.stopPrank();
        assertEq(address(prediction.keeperAddress()), _address);
    }
    function testSetOracleUpdateAllowance(uint256 _amount) public{
        vm.startPrank(prediction.adminAddress());
        prediction.pause();
        prediction.setOracleUpdateAllowance(_amount);
        vm.stopPrank();
        assertEq(prediction.oracleUpdateAllowance(), _amount);
    }
    function testSetFee(uint256 _amount) public{
        vm.assume(_amount != 0 );
        vm.assume(_amount < 1000 );
        vm.startPrank(prediction.adminAddress());
        prediction.pause();
        prediction.setFee(_amount);
        vm.stopPrank();
        assertEq(prediction.fee(), _amount);
    }
    function testSetAdmin(address _address) public{
        vm.assume(_address != address(0));
        vm.startPrank(prediction.owner());
        prediction.setAdmin(_address);
        vm.stopPrank();
    }
    function testPause() public {
        vm.startPrank(prediction.adminAddress());
        prediction.pause();
        vm.stopPrank();
        assertTrue(prediction.paused());
    }
    function testEndToEnd() public {
        vm.startPrank(prediction.operatorAddress());
        
        //Set Inflation Feed at 9.007%
        inflationFeedHelper.setinflationWei(9007440898766211072);
        console.log("Starting Rate: ",uint(inflationFeedHelper.inflationWei()));
        
        // Genesis Start Round
        console.log(" ");
        console.log("Genesis Round starting");
        prediction.genesisStartRound();
        console.log("Genesis Start Once: ", prediction.genesisStartOnce());
        console.log("Oracle Round ID: ", prediction.oracleLatestRoundId());
        console.log(" ");

        // Increment Oracle ID and Inflation rate
        //Set inflation feed at 9.107%
        console.log(" ");
        console.log("Simulating Oracle Run");
        console.log("Start Round ID: ", inflationFeedHelper.roundId());
        console.log("Start Rate: ",uint(inflationFeedHelper.inflationWei()));
        inflationFeedHelper.setinflationWei(9107440898766211072);
        inflationFeedHelper.incrementRoundID();
        console.log("New Round ID: ", inflationFeedHelper.roundId());
        console.log("Locking Rate: ",uint(inflationFeedHelper.inflationWei()));
        console.log(" ");

        // Warp by IntervalSeconds
        console.log(" ");
        console.log("Warping time forward by interval seconds");
        console.log("Before warp: ",block.timestamp);
        vm.warp(block.timestamp + prediction.intervalSeconds());
        console.log("After warp: ",block.timestamp);
        console.log(" ");

        // Genesis Lock Round
        // this will set the lockRate for round 1
        console.log(" ");
        console.log("Locking the prediction");
        prediction.genesisLockRound();
        console.log("Genesis Lock Once:", prediction.genesisLockOnce());
        console.log(" ");

        // Warp again by IntervalSeconds
        console.log(" ");
        console.log("Warping time forward by interval seconds");
        console.log("Before warp: ",block.timestamp);
        vm.warp(block.timestamp + prediction.intervalSeconds());
        console.log("After warp: ",block.timestamp);
        console.log(" ");

        // Increment Oracle ID and Inflation rate
        // Set inflation feed at 9.2%
        // this will set the closeRate for round 1 and lockRate for round 2
        console.log(" ");
        console.log("Simulating Oracle Run");
        console.log("Start Round ID: ", inflationFeedHelper.roundId());
        console.log("Start Rate: ",uint(inflationFeedHelper.inflationWei()));
        inflationFeedHelper.setinflationWei(9207440898766211072);
        inflationFeedHelper.incrementRoundID();
        console.log("New Round ID: ", inflationFeedHelper.roundId());
        console.log("Closing Rate: ",uint(inflationFeedHelper.inflationWei()));
        console.log(" ");
        
        // Prediction Execute Round
        // this will end the first epoch and also lock round 2
        prediction.executeRound();

        vm.stopPrank();

        // Warp again by 2 hours
        console.log(" ");
        console.log("Warping time forward by 2 hours");
        console.log("Before warp: ",block.timestamp);
        vm.warp(block.timestamp + 7200);
        console.log("After warp: ",block.timestamp);
        console.log(" ");
        
        // hand out test eth
        vm.deal(betsOver, 10 ether);
        vm.deal(betsUnder, 10 ether);

        // betsOver bets... over       
        vm.startPrank(betsOver);
        prediction.betOver{value:1000000000000000000}(3);
        vm.stopPrank();

        // betsUnder bets under
        vm.startPrank(betsUnder);
        prediction.betUnder{value:1000000000000000000}(3);
        vm.stopPrank();

        // go back to pranking
        vm.startPrank(prediction.operatorAddress());

        // Warp again by IntervalSeconds
        console.log(" ");
        console.log("Warping time forward by interval seconds");
        console.log("Before warp: ",block.timestamp);
        vm.warp(block.timestamp + (prediction.intervalSeconds())-7200);
        console.log("After warp: ",block.timestamp);
        console.log(" ");

        // Increment Oracle ID and Inflation rate
        // Set inflation feed at 9.3%
        // this will set the close rate for round 2 and lockrate for round 3 
        console.log(" ");
        console.log("Simulating Oracle Run");
        console.log("Start Round ID: ", inflationFeedHelper.roundId());
        console.log("Start Rate: ",uint(inflationFeedHelper.inflationWei()));
        inflationFeedHelper.setinflationWei(9307440898766211072);
        inflationFeedHelper.incrementRoundID();
        console.log("New Round ID: ", inflationFeedHelper.roundId());
        console.log("Closing Rate: ",uint(inflationFeedHelper.inflationWei()));
        console.log(" ");

        // execute another round
        // this will end the second round and then lock round 3
        prediction.executeRound();

        // Warp again by IntervalSeconds
        console.log(" ");
        console.log("Warping time forward by interval seconds");
        console.log("Before warp: ",block.timestamp);
        vm.warp(block.timestamp + prediction.intervalSeconds());
        console.log("After warp: ",block.timestamp);
        console.log(" ");

        // Increment Oracle ID and Inflation rate
        // Set inflation feed at 9.4%
        // this will set the close rate for round 2 and lockrate for round 3 
        console.log(" ");
        console.log("Simulating Oracle Run");
        console.log("Start Round ID: ", inflationFeedHelper.roundId());
        console.log("Start Rate: ",uint(inflationFeedHelper.inflationWei()));
        inflationFeedHelper.setinflationWei(9407440898766211072);
        inflationFeedHelper.incrementRoundID();
        console.log("New Round ID: ", inflationFeedHelper.roundId());
        console.log("Closing Rate: ",uint(inflationFeedHelper.inflationWei()));
        console.log(" ");

        // execute another round
        // this will end round 3 and then lock round 4
        prediction.executeRound();
        
        // change to the admin address
        vm.stopPrank();
        vm.startPrank(prediction.adminAddress());
        

        // Set the Admin address balance to 0
        vm.deal(prediction.adminAddress(),0 ether);

        // Print balance before and after claiming the fees
        console.log("Before Fee Claim: ",(prediction.adminAddress()).balance);
        prediction.claimFee();
        console.log("After Fee Claim: ",(prediction.adminAddress()).balance);

        // Warp again by 5 min
        console.log(" ");
        console.log("Warping time forward by interval seconds");
        console.log("Before warp: ",block.timestamp);
        vm.warp(block.timestamp + 300);
        console.log("After warp: ",block.timestamp);
        console.log(" ");

        // change to the winner address (betsOver)
        vm.stopPrank();
        vm.startPrank(betsOver);

        //claim winning as betsOver
        console.log("Before Claim: ",address(betsOver).balance);
        prediction.claim(tempEpoch);
        console.log("After Claim: ",address(betsOver).balance);

    }
    
}
