// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "../PredictionKeeper.sol";
import "../Prediction.sol";
import {console} from "forge-std/console.sol";

contract PredictionKeeperTest is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    Prediction public prediction;
    PredictionKeeper public predictionKeeper;
    address public oracleAddress = 0xADf2796d3dfcA818a2aceBCDb33F041cD12459BE;
    address public operatorAddress = 0x37398D31E42060d805DA39D9b4Ff4290a0fbbc03;
    uint256 public intervalSeconds = 86400;
    uint256 public bufferSeconds = 30;
    uint256 public minimumBetAmount = 100000000000000;
    uint256 public oracleUpdateAllowance = 30;
    uint256 public fee = 300;
    function setUp() public {
        prediction = new Prediction(oracleAddress,msg.sender,operatorAddress,intervalSeconds,bufferSeconds,minimumBetAmount,oracleUpdateAllowance,fee);
    }
    function testSetPredictionContract(address _address) public {
        vm.assume(_address != address(0));
        vm.startPrank(predictionKeeper.owner());
        predictionKeeper.setPredictionContract(_address);
        vm.stopPrank();
        assertEq(predictionKeeper.PredictionContract(),_address);
    }
}