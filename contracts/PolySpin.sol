// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "../node_modules/@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PolySpin is VRFConsumerBase {
    struct Bet {
        address addr;
        uint256 multiplier;
        uint256 betSize;
    }

    bytes32 private _keyHash;
    uint256 private _fee;
    address payable public owner;
    mapping(bytes32 => Bet) private bets;
    mapping(address => uint256) public winnings;

    event GameStarted(bytes32 indexed requestId, uint256 multiplier, uint256 betSize);
    event GameWon(bytes32 indexed requestId, uint256 indexed result);
    event GameLost(bytes32 indexed requestId, uint256 indexed result);
    event WinningsWithdrew(address indexed user, uint256 indexed amount);
    event ContractFunded(uint256 indexed amount);
    event ContractWithdrew(uint256 indexed amount);

    constructor(
        address vrfCoordinator,
        address link,
        bytes32 keyHash,
        uint256 fee
    ) public VRFConsumerBase(vrfCoordinator, link) {
        _keyHash = keyHash;
        _fee = fee;
        owner = msg.sender;
    }

    modifier onlyOwner(){
        require(msg.sender == owner, "Must be contract owner");
        _;
    }

    receive() external payable {
        emit ContractFunded(msg.value);
    }

    function withdraw() public onlyOwner returns(bool)  {
        uint256 val = address(this).balance;
        owner.transfer(val);
        emit ContractWithdrew(val);
        return true;
    }

    function withdrawLink() public onlyOwner returns(bool)  {
        IERC20 token = IERC20(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        require(token.transfer(msg.sender, token.balanceOf(address(this))), "Transfer failed");
        return true;
    }

    function spinWheel(uint256 multiplier)
        public
        payable
        returns (bytes32 requestId)
    {
        require(
            LINK.balanceOf(address(this)) >= _fee,
            "Not enough LINK to pay fee"
        );
        require(
            multiplier == 2 ||
                multiplier == 3 ||
                multiplier == 5 ||
                multiplier == 10,
            "Invalid multiplier"
        );
        require(msg.value > 0.00000001 ether, "Under minimum bet");
        require(msg.value < 1 ether, "Over maximum bet");
        require(multiplier * msg.value < address(this).balance, "Contract funds low");

        requestId = requestRandomness(_keyHash, _fee);
        Bet memory bet;
        bet.addr = msg.sender;
        bet.multiplier = multiplier;
        bet.betSize = msg.value;
        bets[requestId] = bet;
        emit GameStarted(requestId, multiplier, msg.value);
    }

    function getBalance() public view returns(uint){
        return address(this).balance;
    }

    function withdrawWinnings() public returns(bool) {
        require(winnings[msg.sender] > 0 ether, "No winnings to claim");

        uint256 currentWinnings = winnings[msg.sender];
        winnings[msg.sender] = 0;
        msg.sender.transfer(currentWinnings);

        emit WinningsWithdrew(msg.sender, currentWinnings);
        return true;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        uint256 d20Value = randomness.mod(34).add(1);
        uint256 result;
        if (d20Value < 16) {
            result = 2;
        } else if(d20Value < 26) {
            result = 3;
        } else if(d20Value < 32) {
            result = 5;
        } else if(d20Value < 35) {
            result = 10;
        }

        Bet memory currentBet = bets[requestId];

        if (currentBet.multiplier == result) {
            uint256 currentWinnings = result * currentBet.betSize;
            winnings[currentBet.addr] += currentWinnings;
            emit GameWon(requestId, result);
        } else {
            emit GameLost(requestId, result);
        }
    }
}
