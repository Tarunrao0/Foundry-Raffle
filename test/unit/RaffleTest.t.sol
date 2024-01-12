//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    /**Events */
    event EnterredRaffle(address indexed player);

    address public PLAYER = makeAddr("player1");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    modifier RaffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier RaffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        _;
    }

    modifier TimePassed() {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////////////
    // enterRaffle         //
    /////////////////////////

    function testRaffleRevertsWhenYouDontPayEnought() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public RaffleEntered {
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        // Arrange
        vm.prank(PLAYER);

        // Act / Assert
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnterredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testRaffleDoesntAllowPlayersWhenRaffleIsCalculating()
        public
        RaffleEnteredAndTimePassed
    {
        //Arrange
        // vm.prank(PLAYER);
        //simulating perform upKeep conditions
        //1) Needs to have players
        // raffle.enterRaffle{value: entranceFee}();
        //2) Time has Passed
        // vm.warp(block.timestamp + interval + 1);
        // optional but definetly a good option (makes sure enough blocks have been used)
        // vm.roll(block.number + 1);
        //3)Contract has Balance. Since we entered PLAYER with value entranceFee the contract definetly has some balance rn
        //All the bools have returned TRUE lets run PerformUpkeep so that the RaffleState reaches the Calculating phase
        raffle.performUpkeep("");
        //Now lets try entering the RAFFLE!!!
        //Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /////////////////////////
    // checkUpkeep         //
    /////////////////////////
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public TimePassed {
        //Arrange
        /**time passed */

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //Assert
        /**asserting that it doesnt pass */
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen()
        public
        RaffleEnteredAndTimePassed
    {
        raffle.performUpkeep("");

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed()
        public
        RaffleEntered
    {
        vm.warp(block.timestamp);
        vm.roll(block.number);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsTrueWhenParametersAreGood()
        public
        RaffleEnteredAndTimePassed
    {
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    /////////////////////////
    // performUpkeep       //
    /////////////////////////

    function testPerformUpKeepCanOnlyRunIfCheckUpKeepIsTrue()
        public
        RaffleEnteredAndTimePassed
    {
        //Act
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        RaffleEnteredAndTimePassed
    {
        // Arrange
        //Act
        vm.recordLogs(); //automatically records events emitted and save all the outputs
        raffle.performUpkeep(""); //emits the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        //all events in foundry are of bytes32 datatype
        // 1 because 0 is the first event emitted by the mock contract and our event is the second one being emitted
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // requestId = raffle.getLastRequestId();
        assert(uint256(requestId) > 0);
        assert(uint(raffleState) == 1); // 0 = open, 1 = calculating
    }

    /////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerormUpkeep(
        uint256 randomRequestId
    ) public RaffleEnteredAndTimePassed skipFork {
        //Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFullfillRandomWordsPicksAWinnerAndSendsMoney()
        public
        RaffleEnteredAndTimePassed
        skipFork
    {
        address expectedWinner = address(1);

        //Arrange
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i)); //address(1) address(2)
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        vm.recordLogs(); //automatically records events emitted and save all the outputs
        raffle.performUpkeep(""); //emits the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        //all events in foundry are of bytes32 datatype
        // 1 because 0 is the first event emitted by the mock contract and our event is the second one being emitted
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
