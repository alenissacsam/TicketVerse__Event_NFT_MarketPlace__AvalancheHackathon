// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {TicketMarketplace} from "../src/TicketMarketplace.sol";
import {Script} from "forge-std/Script.sol";

contract DeployTicketMarketPlace is Script {
    function run(
        address _platformAddress,
        uint256 _platformFeePercent,
        uint256 _maxAuctionDuration,
        address _userVerfierAddress
    ) external returns (address) {
        vm.startBroadcast();

        TicketMarketplace ticketMarketplace = new TicketMarketplace(
            _platformAddress,
            _platformFeePercent,
            _maxAuctionDuration,
            _userVerfierAddress
        );

        vm.stopBroadcast();
        return address(ticketMarketplace);
    }
}
