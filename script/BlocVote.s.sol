// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BlocVote} from "../src/BlocVote.sol";
import {ContractFactory} from "../src/ContractFactory.sol";

contract BlocVoteScript is Script {
    function run() public {
        vm.startBroadcast();

        ContractFactory factory = new ContractFactory();
        factory.deploy();

        vm.stopBroadcast();
    }
}
