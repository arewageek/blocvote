// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BlocVote} from './BlocVote.sol';

contract ContractFactory {
    BlocVote[] public blocvoteContracts;

    event BlocVoteDeployed(address indexed chairman, address indexed blocVote);

    function deploy() external returns (address) {
        BlocVote blocVote = new BlocVote(msg.sender);
        blocvoteContracts.push(blocVote);

        emit BlocVoteDeployed(msg.sender, address(blocVote));

        return address(blocVote);
    }

    function deployedCount() external view returns (uint) {
        return blocvoteContracts.length;
    }
}
