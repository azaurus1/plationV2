// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPrediction {

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

    function rounds(uint256 epoch)
        external
        view
        returns (Round memory);
    function genesisStartOnce() external view returns (bool);

    function genesisLockOnce() external view returns (bool);

    function paused() external view returns (bool);

    function currentEpoch() external view returns (uint256);

    function bufferSeconds() external view returns (uint256);

    function intervalSeconds() external view returns (uint256);

    function genesisStartRound() external;

    function pause() external;
    function unpause() external;

    function genesisLockRound() external;

    function executeRound() external;





}