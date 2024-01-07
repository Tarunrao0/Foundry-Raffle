//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/**
 * @title Enter the Raffle and be the LUCKY WINNER!
 * @author Tarun Rao
 * @notice This contract is creating a sample raffle
 * @dev Implements the chainlink VRFv2
 */

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    /**Errors */

    error Raffle__NotEnoughEthSent();
    error Raffle__NotEnoughTimeHasPassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();

    /**Enum */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /**State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    /**@dev Duration of the lottery in seconds */
    uint256 private s_LastTimeStamp;
    address payable[] private s_players;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**Events */
    event EnterredRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    )
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_LastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnterredRaffle(msg.sender);
    } 

    function checkUpkeep(
        bytes memory /*checkData */
    )public view returns (bool upkeepNeeded, bytes memory /* performData */){

    }

    function pickWinner() public {
        if ((block.timestamp - s_LastTimeStamp) < i_interval) {
            revert Raffle__NotEnoughTimeHasPassed();
        }
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit, //Gas Limit
            NUM_WORDS //number of winners
        );
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;

        s_players = new address payable[](0);
        s_LastTimeStamp = block.timestamp;

        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(winner);
    }

    /**Getter Functions */

    function getEntranceFee() public returns (uint256) {
        return i_entranceFee;
    }
}
