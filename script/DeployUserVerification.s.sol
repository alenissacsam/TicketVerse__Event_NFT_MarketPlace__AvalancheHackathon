//SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {UserVerification} from "../src/UserVerification.sol";
import {Script} from "forge-std/Script.sol";

/**
 * @title DeployUserVerification
 * @author alenissacsam
 * @dev A script to deploy the UserVerification contract.
 */

contract DeployUserVerification is Script {
    function run() external returns (address) {
        vm.startBroadcast();

        UserVerification userVerification = new UserVerification();

        vm.stopBroadcast();
        return address(userVerification);
    }
}
