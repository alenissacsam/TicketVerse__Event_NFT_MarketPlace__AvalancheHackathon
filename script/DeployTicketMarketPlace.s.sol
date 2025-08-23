// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {TicketMarketplace} from "../src/TicketMarketplace.sol";
import {Script} from "forge-std/Script.sol";

contract DeployTicketMarketPlace is Script {
    function run(
        address _platformAddress,
        uint256 _platformFeePercent // Note: maxAuctionDuration is now a constant in the contract
    ) external returns (address ticketMarketplaceAddress) {
        vm.startBroadcast();

        TicketMarketplace ticketMarketplace = new TicketMarketplace(
            _platformAddress,
            _platformFeePercent, // e.g., 250 for 2.5%
            address(0) // TODO: Replace with actual UserVerifier address
        );

        vm.stopBroadcast();
        ticketMarketplaceAddress = address(ticketMarketplace);
    }
}
