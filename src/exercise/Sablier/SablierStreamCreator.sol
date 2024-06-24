// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "oz/utils/math/SafeCast.sol";

import {ud60x18} from "@prb/math/src/UD60x18.sol";
import {ud2x18} from "@prb/math/src/UD2x18.sol";
import {ISablierV2LockupLinear} from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import {ISablierV2LockupDynamic} from "@sablier/v2-core/src/interfaces/ISablierV2LockupDynamic.sol";
import {Broker, LockupLinear, LockupDynamic} from "@sablier/v2-core/src/types/DataTypes.sol";

abstract contract SablierStreamCreator {
    using SafeCast for uint256;
    //@note  maybe we need to move this to the exercise contract??
    ISablierV2LockupLinear public immutable LOCKUP_LINEAR; 
    //Mainnet Addr ISablierV2LockupLinear(0xAFb979d9afAd1aD27C5eFf4E27226E3AB9e5dCC9);

    ISablierV2LockupDynamic public immutable LOCKUP_DYNAMIC; 
    //Mainnet Addr ISablierV2LockupDynamic(0x7CC7e125d83A581ff438608490Cc0f7bDff79127);

    constructor(address lockupLinear_, address lockupDynamic_) {
        LOCKUP_LINEAR = ISablierV2LockupLinear(lockupLinear_);
        LOCKUP_DYNAMIC = ISablierV2LockupDynamic(lockupDynamic_);
    }

    /////////////////////////////////
    /// Stream Creation Functions ///
    /////////////////////////////////

    function createLinearStream(uint40 cliffDuration_, uint40 totalDuration_, uint256 amount_, address token_, address recipient_)
        internal
        virtual
        returns (uint256 streamId)
    {

        // Approve the Sablier contract to pull the tokens from this contract
        IERC20(token_).approve(address(LOCKUP_LINEAR), amount_);

        LockupLinear.CreateWithDurations memory params;
        // Declare the function parameters
        params.sender = address(this); // The sender will be able to cancel the stream
        params.recipient = recipient_; // The recipient of the streamed assets
        params.totalAmount = amount_.toUint128(); // Total amount is the amount inclusive of all fees
        params.asset = IERC20(token_); // The streaming asset
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.transferable = true; // Whether the stream will be transferable or not @note do we want this?
        params.durations = LockupLinear.Durations({
            //@note just use this as a "locked" stream set the cliff duration to the time you wish to release the tokens and the totalDuration to clifftime + 1 seconds
            cliff: cliffDuration_, // Assets will be unlocked / begin streaming only after this time @note I think we want to keep this a constant
            total: totalDuration_ // Setting a total duration of the stream
        });
        params.broker = Broker(address(0), ud60x18(0)); // Optional parameter for charging a fee @note we take fees in other places so no need for this I believe

        // Create the LockupLinear stream using a function that sets the start time to `block.timestamp`
        streamId = LOCKUP_LINEAR.createWithDurations(params);
    }

    //@note could turn the amount0_ and amount1_ into an array of ammounts. Would need to loop through array to pass them into segments here
    function createDynamicStream(uint128 totalAmount_, uint128 amount0_, uint128 amount1_, address token_, address recipient_)
        internal
        virtual 
        returns (uint256 streamId)
    {
        // Transfers the tokens to be streamed to this contract @note maybe this needs to go somewhere else
        IERC20(token_).transferFrom(msg.sender, address(this), totalAmount_);

        // Approve the Sablier contract to pull the tokens from this contract
        IERC20(token_).approve(address(LOCKUP_DYNAMIC), totalAmount_);

        LockupDynamic.CreateWithMilestones memory params;

        // Declare the function parameters
        params.sender = msg.sender; // The sender will be able to cancel the stream
        params.startTime = uint40(block.timestamp + 100 seconds);
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.transferable = true; // Whether the stream will be transferable or not
        params.recipient = recipient_; // The recipient of the streamed assets
        params.totalAmount = totalAmount_; // Total amount is the amount inclusive of all fees
        params.asset = IERC20(token_); // The streaming asset
        params.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

        // Declare some dummy segments
        // amount - uint128: The amount of tokens to stream in the segment.
        // exponent - ud2x18: The exponent of the streaming function in the segment. This changes the curve of the stream.
        // milestone - uint40: The Unix timestamp at which the segment will end.
        params.segments = new LockupDynamic.Segment[](2);
        params.segments[0] = LockupDynamic.Segment({amount: amount0_, exponent: ud2x18(1e18), milestone: uint40(block.timestamp + 4 weeks)});
        params.segments[1] = (LockupDynamic.Segment({amount: amount1_, exponent: ud2x18(3.14e18), milestone: uint40(block.timestamp + 52 weeks)}));

        // Create the LockupDynamic stream
        streamId = LOCKUP_DYNAMIC.createWithMilestones(params);
    }
    
}
