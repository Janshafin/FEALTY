// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title VoteSignal
/// @notice The exact signal a World ID proof must commit to, binding a proof to one voter,
///         one ballot and one choice. The off-chain client must build the identical string.
library VoteSignal {
    /// @param voter The voting address.
    /// @param ballotId The ballot being voted on.
    /// @param support Whether the vote is yes.
    /// @return The signal bytes: lowercase hex address, ballot id and choice joined by colons.
    function encode(address voter, uint256 ballotId, bool support) internal pure returns (bytes memory) {
        return bytes.concat(bytes(Strings.toHexString(voter)), ":", bytes(Strings.toString(ballotId)), ":", support ? bytes("1") : bytes("0"));
    }
}
