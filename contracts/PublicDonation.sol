// SPDX-License-Identifier: MIT                                                

pragma solidity ^0.8.18;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IMainNFT {
    function getUniswapRouterAddress() external view returns (address);
    function ownerOf(uint256) external view returns (address);
    function owner() external view returns (address);
    function onlyAuthor(address, uint256) external pure returns (bool);
    function isAddressExist(address, address[] memory) external pure returns (bool);
    function contractFeeForAuthor(uint256, uint256) external view returns(uint256);
    function commissionCollector() external view returns (address);
    function addAuthorsRating(address, uint256, uint256) external;
    function setVerfiedContracts(bool, address) external;
}

contract PublicDonation is  ReentrancyGuard {
    using SafeMath for uint256;

    IMainNFT mainNFT;

    mapping(uint256 => address[]) donateTokenAddressesByAuthor;

    event Received(address indexed sender, uint256 value);
    event Donate(address indexed sender, address indexed token, uint256 value, uint256 indexed author);

    modifier onlyAuthor(uint256 author) {
        require(mainNFT.onlyAuthor(msg.sender, author), "Only for Author");
        _;
    }

    modifier supportsERC20(address _address){
        require(
            _address == address(0) || IERC20(_address).totalSupply() > 0 && IERC20(_address).allowance(_address, _address) >= 0,
            "Is not ERC20"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner(), "Only owner");
        _;
    }

    constructor(address mainNFTAddress) {
        mainNFT = IMainNFT(mainNFTAddress);
        mainNFT.setVerfiedContracts(true, address(this));
    }

    /***************Author options BGN***************/
    function addDonateAddress(address tokenAddress, uint256 author) supportsERC20(tokenAddress) onlyAuthor(author) public {
        address[] storage tokens = donateTokenAddressesByAuthor[author];
        require(!mainNFT.isAddressExist(tokenAddress, tokens), "Already exists");
        tokens.push(tokenAddress);
    }

    function removeDonateAddress(address tokenAddress, uint256 author) supportsERC20(tokenAddress) onlyAuthor(author) public {
        address[] storage tokens = donateTokenAddressesByAuthor[author];
        require(mainNFT.isAddressExist(tokenAddress, tokens), "Not exist");
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenAddress) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }
    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function getAllDonateTokenAddressesByAuthor(uint256 author) public view returns (address[] memory){
        return donateTokenAddressesByAuthor[author];
    }

    function paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        uint256 amount = value - contractFee;
        (bool success1, ) = commissionCollector().call{value: contractFee}("");
        (bool success2, ) = ownerOf(author).call{value: amount}("");
        require(success1 && success2, "fail");
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        address[] memory tokensByAuthor = donateTokenAddressesByAuthor[author];
        require(mainNFT.isAddressExist(tokenAddress, tokensByAuthor), "Token not exist");

        IERC20 token = IERC20(tokenAddress);
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        token.transferFrom(sender, commissionCollector(), contractFee);
        uint256 amount = tokenAmount - contractFee;
        token.transferFrom(sender, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }

    function donateEth(uint256 author) public payable{        
        require(msg.value >= 10**6, "Low value");
        paymentEth(author, msg.value);
        emit Donate(msg.sender, address(0), msg.value, author);
    }

    function donateToken(address tokenAddress, uint256 tokenAmount, uint256 author) public{
        require(tokenAmount > 0, "Low value");
        paymentToken(msg.sender, tokenAddress, tokenAmount, author);
        emit Donate(msg.sender, tokenAddress, tokenAmount, author);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function owner() public view returns(address){
        return mainNFT.owner();
    }

    function commissionCollector() public view returns(address){
        return mainNFT.commissionCollector();
    }

    function ownerOf(uint256 author) public view returns (address){
        return mainNFT.ownerOf(author);
    }

    function setIMainNFT(address mainNFTAddress) public onlyOwner{
        mainNFT = IMainNFT(mainNFTAddress);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        (bool success, ) = commissionCollector().call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_address);
        uint256 amount = token.balanceOf(address(this));
        token.transfer(commissionCollector(), amount);
    }
    /***************Support END**************/

    receive() external payable {
        (bool success, ) = commissionCollector().call{value: msg.value}("");
        require(success, "fail");
        emit Received(msg.sender, msg.value);
    }
}