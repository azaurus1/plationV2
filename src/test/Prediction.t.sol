// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import "forge-std/Vm.sol";
import "../Prediction.sol";


contract PredictionTest is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    Prediction public prediction;
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

    function testOracleAddress() public{
        assertEq(address(prediction.oracle()),oracleAddress);
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
    //function testSetOracle(address _address) public{
    //    vm.startPrank(prediction.adminAddress());
    //    vm.assume(_address != address(0));
    //    prediction.pause();
    //    prediction.setOracle(_address);
    //    vm.stopPrank();
    //    assertEq(address(prediction.oracle()), _address);
    //}
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
    function testSetAdmin(address _address) public{}
}
