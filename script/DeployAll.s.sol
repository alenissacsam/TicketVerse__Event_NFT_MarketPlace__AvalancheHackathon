// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {DeployEventFactory} from "./DeployEventFactory.s.sol";
import {DeployTicketMarketPlace} from "./DeployTicketMarketPlace.s.sol";
import {DeployUserVerification} from "./DeployUserVerification.s.sol";
import {Script} from "forge-std/Script.sol";

contract DeployAll is Script {
    address _platformAddress = msg.sender;
    uint256 _platformFeePercent = 500;
    uint256 _maxAuctionDuration = 30 days;

    function run() external returns (address, address, address) {
        DeployUserVerification deployUserVerification = new DeployUserVerification();
        address userVerification = deployUserVerification.run();

        DeployEventFactory deployEventFactory = new DeployEventFactory();
        address eventFactory = deployEventFactory.run(
            _platformAddress,
            userVerification
        );

        DeployTicketMarketPlace deployTicketMarketPlace = new DeployTicketMarketPlace();
        address ticketMarketplace = deployTicketMarketPlace.run(
            _platformAddress,
            _platformFeePercent,
            _maxAuctionDuration,
            userVerification
        );

        return (
            address(userVerification),
            eventFactory,
            address(ticketMarketplace)
        );
    }
}
