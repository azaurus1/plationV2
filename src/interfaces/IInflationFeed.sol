// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface InflationFeedInterface {

    function requestInflationWei() external returns (bytes32 requestId);
    function latestRoundData() external view returns (uint80 _roundId, int256 _inflationWei, uint256 _timestamp);

}