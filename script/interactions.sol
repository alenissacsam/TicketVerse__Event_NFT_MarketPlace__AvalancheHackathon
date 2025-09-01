// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {EventFactory} from "../src/EventFactory.sol";
import {EventTicket} from "../src/EventTicket.sol";
import {UserVerification} from "../src/UserVerification.sol";
import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "@foundry-devops/src/DevOpsTools.sol";

contract UserVerificationInteraction is Script {
    function run() public view {
        // This script checks the verification status of different users.

        // 1. Get the most recently deployed UserVerification contract.
        UserVerification userVerification =
            UserVerification(DevOpsTools.get_most_recent_deployment("UserVerification", block.chainid));
        console.log("UserVerification contract address:", address(userVerification));

        // 2. Check the owner of the contract. The owner should be verified by the constructor.
        address owner = userVerification.owner();
        console.log("Contract owner:", owner);
        console.log("Is owner verified?", userVerification.isVerified(owner));

        // 3. Check a random, unverified address. This should return false.
        address randomUser = address(0xDEADBEEF);
        console.log("Checking random user:", randomUser);
        console.log("Is random user verified?", userVerification.isVerified(randomUser));
    }
}

contract VerifyUserInteraction is Script {
    function run() public {
        UserVerification userVerification =
            UserVerification(DevOpsTools.get_most_recent_deployment("UserVerification", block.chainid));

        vm.startBroadcast();
        userVerification.verifyUser(0xa6253aC3Cf4CABa9Fb7B46CeF108E5eF97F3704f);
        vm.stopBroadcast();

        // Check that the user is now verified.
        require(userVerification.isVerified(0xa6253aC3Cf4CABa9Fb7B46CeF108E5eF97F3704f), "User should be verified");
    }
}

contract CreateEventInteraction is Script {
    function run() public {
        EventFactory eventFactory = EventFactory(DevOpsTools.get_most_recent_deployment("EventFactory", block.chainid));
        uint256 creationFee = eventFactory.eventCreationFee();
        console.log("EventFactory Address:", address(eventFactory));
        console.log("Event Creation Fee:", creationFee);

        vm.startBroadcast();
        eventFactory.createEvent{value: creationFee}(
            EventFactory.CreateEventParams({
                name: "Coldplay",
                symbol: "CP",
                maxSupply: 10000,
                baseMintPrice: 0.0001 ether,
                organizerPercentage: 9500, // Corrected: 95% in basis points
                royaltyFeePercentage: 200, // Corrected: 2% in basis points
                eventStartTime: block.timestamp + 30 days,
                eventEndTime: block.timestamp + 31 days,
                maxMintsPerUser: 5,
                vipConfig: EventFactory.VIPConfig({
                    totalVIPSeats: 1000,
                    vipSeatStart: 1, // Corrected: Must be >= 1
                    vipSeatEnd: 1000,
                    vipHoldingPeriod: 0,
                    vipEnabled: true
                }),
                vipMintPrice: 0.001 ether,
                waitlistEnabled: false,
                whitelistSaleDuration: 0,
                initialWhitelist: new address[](0), // Corrected: Empty array syntax
                venue: "Hyderabad",
                eventDescription: "Coldplay Concert",
                seatCount: 10000,
                vipTokenURIBase: "https://ipfs.io/ipfs/bafkreiariqy4dml42gvqlxs6g673k7wtixhkawqajxbyuaz3evmlggvjfy", // Corrected: Encased in quotes
                nonVipTokenURIBase: "https://ipfs.io/ipfs/bafkreiemi4ycoqlcys2davu44wsmevdqbnvhlxwd4wegys6e3uzfm4ra7i" // Corrected: Encased in quotes
            })
        );
        vm.stopBroadcast();
    }
}

contract MintInteractions is Script {
    function run() public {
        EventFactory eventFactory = EventFactory(DevOpsTools.get_most_recent_deployment("EventFactory", block.chainid));

        EventTicket eventTicket = EventTicket(eventFactory.getAllDeployedEvents()[2]);
        console.log("EventTicket Address:", address(eventTicket));
        vm.startBroadcast();
        eventTicket.mintTicket{value: 0.0001 ether}("Coldplay Concert", 1002);
        vm.stopBroadcast();
    }
}
