// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BlocVote} from "./BlocVote.sol";

/// @title ContractFactory
/// @notice Deploys and tracks independent BlocVote election instances.
/// @dev Anyone may call `deploy()` — each caller becomes the chairman of their
///      own election contract. All deployed addresses are tracked in the
///      `blocvoteContracts` array for discoverability.
contract ContractFactory {
    BlocVote[] public blocvoteContracts;

    event BlocVoteDeployed(address indexed chairman, address indexed blocVote);

    /// @notice Deploy a new BlocVote election contract with the caller as chairman.
    /// @return addr Address of the newly deployed BlocVote contract.
    /// @dev The `reentrancy-events` Forge lint warning on this function is a known
    ///      false positive. `new BlocVote()` does not call back into this contract —
    ///      there is no reentrant path. State is updated before the event is emitted,
    ///      following the Checks-Effects-Events pattern.
    function deploy() external returns (address addr) {
        BlocVote blocVote = new BlocVote(msg.sender);
        addr = address(blocVote);

        // Effect: record deployed instance before emitting the event.
        blocvoteContracts.push(blocVote);

        emit BlocVoteDeployed(msg.sender, addr);
    }

    /// @notice Returns the total number of BlocVote contracts deployed via this factory.
    function deployedCount() external view returns (uint256) {
        return blocvoteContracts.length;
    }
}
