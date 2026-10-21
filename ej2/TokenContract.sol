// SPDX-License-Identifier: Unlicenced
pragma solidity 0.8.34;
contract TokenContract {
    address public owner;
    struct Receivers {
        string name;
        uint256 tokens;
    }
    mapping(address => Receivers) public users;
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    constructor() {
        owner = msg.sender;
        users[owner].tokens = 100;
    }
    function double(uint _value) public pure returns (uint) {
        return _value * 2;
    }
    function register(string memory _name) public {
        users[msg.sender].name = _name;
    }
    function giveToken(address _receiver, uint256 _amount) public onlyOwner {
        require(users[owner].tokens >= _amount);
        users[owner].tokens -= _amount;
        users[_receiver].tokens += _amount;
    }

    event ContractBalance(uint256 balance);

    function buyToken(uint256 _tokens) public payable {
        uint256 price = _tokens * 5 ether;

        require(
            msg.value >= price,
            "Debes enviar ETH suficiente (1 token = 5 ether)"
        );
        require(users[owner].tokens >= _tokens, "No hay suficientes tokens");

        users[owner].tokens -= _tokens;
        users[msg.sender].tokens += _tokens;

        uint256 rest = msg.value - price;
        if (rest > 0) {
            (bool success, ) = payable(msg.sender).call{value: rest}("");
            require(success, "Error devolviendo ETH");
        }

        emit ContractBalance(address(this).balance);
    }
}
