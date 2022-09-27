// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "./interfaces/IInflationFeed.sol";


contract InflationFeedKeeper is  Ownable, Pausable {

    InflationFeedInterface public feed;
    address public keeperAddress;

    modifier onlyOwnerOrKeeper(){
        require(msg.sender == owner() || msg.sender == keeperAddress);
        _;
    }

    constructor(address _feed) public{
        feed = InflationFeedInterface(_feed);
    } 

    function updateFeed() external {
        feed.requestInflationWei();
    }

    function setKeeperAddress(address keeperAddress_) public{
        require(keeperAddress_ != address(0));
        keeperAddress = keeperAddress_;
    }

}