// SPDX-License-Identifier: MIT                                                

pragma solidity ^0.8.18;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract MainNFT is ERC721Enumerable, IERC2981, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Strings for uint256;

    uint8 public levels;
    uint16 public royaltyFee = 1000;
    uint256 public totalAmounts;
    uint256 publicSaleTokenPrice = 0.1 ether;
    string public baseURI;
    mapping (uint256 => uint256) public authorsAmounts;
    mapping (address => bool) public verifiedContracts;
    IUniswapV2Router02 public uniswapRouter;

    mapping(uint256 => address) public managers;

    event Received(address indexed sender, uint256 value);

    modifier onlyVerified(address _address){
        require(verifiedContracts[_address], "Is not verified");
        _;
    }

    modifier supportsERC20(address _address){
        require(
            _address == address(0) || IERC20(_address).totalSupply() > 0 && IERC20(_address).allowance(_address, _address) >= 0,
            "Is not ERC20"
        );
        _;
    }

    constructor(address _uniswapRouterAddress, uint8 _levelsCount, string memory _baseURI) ERC721("SocialFi by 0xc0de", "SoFi") {
        uniswapRouter = IUniswapV2Router02(_uniswapRouterAddress);
        levels = _levelsCount;
        baseURI = _baseURI;
    }

    /***************Common interfaces BGN***************/
    function priceToMint(address minter) public view returns(uint256){
        uint256 balance = balanceOf(minter);
        return publicSaleTokenPrice * (2 ** balance);
    }

    function safeMint() public nonReentrant payable {
        require(priceToMint(msg.sender) <= msg.value, "Low value");
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "fail");
        uint256 nextIndex = totalSupply();
        _addAuthorsRating(msg.value, nextIndex);
        _safeMint(msg.sender, nextIndex);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        uint256 thisLevel = (10 ** levels) * authorsAmounts[tokenId] / totalAmounts;
        uint256 uriNumber = myLog10(thisLevel);
        if (uriNumber >= levels){
            uriNumber = levels - 1;
        }
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, uriNumber.toString(), ".json"))
                : "";
    }

    function myLog10(uint256 x) internal pure returns (uint256) {
        uint256 result = 0;
        while (x >= 10){
            x /= 10;
            result += 1;
        }
        return result;
    }

    function onlyAuthor(uint256 author) public view returns (bool){
        return ownerOf(author) == msg.sender || managers[author] == msg.sender;
    }

    function isAddressExist(address _addressToCheck, address[] memory _collection) public pure returns (bool) {
        for (uint i = 0; i < _collection.length; i++) {
            if (_collection[i] == _addressToCheck) {
                return true;
            }
        }
        return false;
    }

    function commissionCollector() public view returns (address){
        return owner();
    }

    function converTokenPriceToEth(address tokenAddress, uint256 tokenAmount) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenAddress;
        path[1] = uniswapRouter.WETH();
        try uniswapRouter.getAmountsOut(tokenAmount, path) returns(uint256[] memory amountsOut){
            return amountsOut[1];
        } catch (bytes memory) {
            return 0;
        }
    }
    /***************Common interfaces END***************/

    /***************Author options BGN***************/
    function addAuthorsRating(address tokenAddress, uint256 tokenAmount, uint256 author) public onlyVerified(msg.sender) {
        uint256 value = tokenAddress == address(0) ? tokenAmount : converTokenPriceToEth(tokenAddress, tokenAmount);
        _addAuthorsRating(value, author);
    }

    function _addAuthorsRating(uint256 value, uint256 author) private {
        totalAmounts += value;
        authorsAmounts[author] += value;
    }

    function setManager(address newManager, uint256 author) public {
        require(ownerOf(author) == msg.sender, "Only owner");
        managers[author] = newManager;
    }

    function contractFeeForAuthor(uint256 author, uint256 amount) public view returns(uint256){
        uint256 thisLevel = (10 ** levels) * authorsAmounts[author] / totalAmounts;
        uint256 contractFee = amount * 2 / ( 100 * (2 ** myLog10(thisLevel)));
        return contractFee > 0 ? contractFee : 1;
    }
    /***************Author options END***************/

    /***************Only for owner BGN***************/
    function setBaseURI(uint8 _levelsCount, string memory _baseURI) external onlyOwner {
        levels = _levelsCount;
        baseURI = _baseURI;
    }

    function setPublicSaleTokenPrice(uint256 _newPrice) external onlyOwner {
        publicSaleTokenPrice = _newPrice;
    }

    function setNewRouter(address _uniswapRouterAddress) external onlyOwner {
        uniswapRouter = IUniswapV2Router02(_uniswapRouterAddress);
    }

    function setVerfiedContracts(bool isVerified, address _address) public onlyOwner {
        verifiedContracts[_address] = isVerified;
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override returns (address receiver, uint256 royaltyAmount) {
        require(_exists(tokenId), "nonexistent");
        return (address(this), (salePrice * royaltyFee) / 10000);
    }    

    function setRoyaltyFee(uint16 fee) external onlyOwner {
        require (fee < 10000, "too high");
        royaltyFee = fee;
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        (bool success, ) = _msgSender().call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_address);
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 amount = tokenBalance;
        token.transfer(_msgSender(), amount);
    }
    /***************Only for owner END**************/

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}