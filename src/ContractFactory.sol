// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BlocVote} from './BlocVote';

contract ContractFactory {
    BlockVote[] blocvoteContracts;

    function deploy() external returns (address) {
        address contr = new BlocVote(msg.sender);
        blocvoteContracts.push(contr);

        return contr;
    }
}