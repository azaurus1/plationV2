// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";


contract InflationFeedHelper  {
  
  int256 public inflationWei;
  uint80 public roundId;

  // Please refer to
  // https://github.com/truflation/quickstart/blob/main/network.md
  // for oracle address. job id, and fee for a given network

  function setinflationWei(int256 _inflationWei) public{
      inflationWei = _inflationWei;
  }

  function incrementRoundID() public {
      roundId += 1;
  }

  function latestRoundData() external view returns (uint80 _roundId, int256 _inflationWei, uint256 _timestamp) {
        _roundId = roundId;
        _inflationWei = inflationWei;
        _timestamp = block.timestamp;
        return (_roundId, _inflationWei, _timestamp);
  }

}