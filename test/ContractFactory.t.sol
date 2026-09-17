// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ContractFactory} from "../src/ContractFactory.sol";
import {BlocVote} from "../src/BlocVote.sol";

contract ContractFactoryTest is Test {
    ContractFactory public factory;

    address caller = address(0xC4A1);

    function setUp() public {
        factory = new ContractFactory();
    }

    function test_DeployMakesCallerTheChairman() public {
        vm.prank(caller);
        address deployed = factory.deploy();

        BlocVote blocVote = BlocVote(deployed);
        assertEq(blocVote.chairman(), caller);
        assertEq(blocVote.deployer(), address(factory), "factory is the deploying account");
    }

    function test_DeployTracksEveryInstance() public {
        vm.prank(caller);
        address first = factory.deploy();
        vm.prank(caller);
        address second = factory.deploy();

        assertEq(factory.deployedCount(), 2);
        assertEq(address(factory.blocvoteContracts(0)), first);
        assertEq(address(factory.blocvoteContracts(1)), second);
        assertTrue(first != second);
    }

    function test_DeployedInstanceIsUsableByItsChairman() public {
        vm.prank(caller);
        BlocVote blocVote = BlocVote(factory.deploy());

        vm.prank(caller);
        blocVote.registerOffice("President");

        (,, bool isValid,) = blocVote.offices(0);
        assertTrue(isValid);

        vm.prank(address(0xBAD));
        vm.expectRevert("unauthorized");
        blocVote.registerOffice("Fake");
    }
}
