//SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {EventFactory} from "../src/EventFactory.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title DeployEventFactory
 * @author alenissacsam
 * @dev A script to deploy the EventFactory contract.
 */

contract DeployEventFactory is Script {
    function run(
        address _platformAddress,
        address _verifierAddress
    ) external returns (address) {
        vm.startBroadcast();

        EventFactory eventFactory = new EventFactory(
            _platformAddress,
            _verifierAddress
        );

        vm.stopBroadcast();
        return address(eventFactory);
    }
}
