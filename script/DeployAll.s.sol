// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {EventFactory} from "../src/EventFactory.sol";
import {DeployEventFactory} from "./DeployEventFactory.s.sol";
import {DeployTicketMarketPlace} from "./DeployTicketMarketPlace.s.sol";
import {DeployUserVerification} from "./DeployUserVerification.s.sol";
import {Script} from "forge-std/Script.sol";

contract DeployAll is Script {
    uint256 _platformFeePercent = 500;

    function run() external returns (address, address, address) {
        address platformAddress = msg.sender;
        DeployUserVerification deployUserVerification = new DeployUserVerification();
        address userVerification = deployUserVerification.run();

        DeployEventFactory deployEventFactory = new DeployEventFactory();
        address eventFactory = deployEventFactory.run(
            platformAddress,
            userVerification
        );

        DeployTicketMarketPlace deployTicketMarketPlace = new DeployTicketMarketPlace();
        address ticketMarketplace = deployTicketMarketPlace.run(
            platformAddress,
            _platformFeePercent,
            userVerification
        );

        vm.startBroadcast();
        EventFactory(eventFactory).addMarketplaceAddress(ticketMarketplace);
        vm.stopBroadcast();

        return (
            address(userVerification),
            eventFactory,
            address(ticketMarketplace)
        );
    }
}
