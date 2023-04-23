// SPDX-License-Identifier: MIT                                                

pragma solidity ^0.8.18;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IMainNFT {
    function ownerOf(uint256) external view returns (address);
    function onlyAuthor(address, uint256) external pure returns (bool);
    function isAddressExist(address, address[] memory) external pure returns (bool);
    function contractFeeForAuthor(uint256, uint256) external view returns(uint256);
    function commissionCollector() external view returns (address);
    function addAuthorsRating(address, uint256, uint256) external;
    function setVerfiedContracts(bool, address) external;
    function converTokenPriceToEth(address, uint256) external view returns(uint256);
}

contract Subscriptions is  ReentrancyGuard {
    using SafeMath for uint256;

    IMainNFT mainNFT;

    struct Discount{
        uint256 period;
        uint256 amountAsPPM; // 1/1000 or 0.1%
    }

    struct Payment{
        address tokenAddress;
        uint256 amount;
        uint256 amountInEth;
        uint256 paymentTime;
    }

    struct Subscription{
        bytes32 hexName;
        bool isActive;
        bool isRegularSubscription;
        uint256 paymetnPeriod;
        address[] tokenAddresses;
        uint256 price;
    }

    struct Participant{
        address participantAddress;
        uint256 subscriptionEndTime;
    }

    mapping(uint256 => mapping(address => bool)) public blackListByAuthor;
    mapping(uint256 => Subscription[]) public subscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => Discount[])) public discountSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => Participant[])) public participantsSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public participantIndex;
    mapping(bytes32 => uint256[2]) public subscriptionIndexByHexName;
    
    mapping(uint256 => mapping(uint256 => Payment[])) public paymentSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => uint256)) public totalPaymentSubscriptionsByAuthoInEth;

    event Received(address indexed sender, uint256 value);
    event NewOneTimeSubscriptionCreated(uint256 indexed author, bytes32 indexed hexName, address[] tokenAddresses, uint256 price, Discount[] discounts);
    event NewRegularSubscriptionCreated(uint256 indexed author, bytes32 indexed hexName, address[] tokenAddresses, uint256 price, uint256 paymetnPeriod, Discount[] discounts);
    event NewSubscription(address indexed participant, uint256 indexed author, uint256 indexed subscriptionId, uint256 subscriptionEndTime, address tokenAddress, uint256 amount);

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
    function addToBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = true;
    }

    function removeBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
    }

    function createNewSubscriptionByEth(
        bytes32 hexName,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            address[] memory tokenAddresses = new address[](1);
            tokenAddresses[0] = address(0);
            createNewSubscriptionByToken(hexName, author, isRegularSubscription, paymetnPeriod, tokenAddresses, price, discountProgramm);
    }

    function createNewSubscriptionByToken(
        bytes32 hexName,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        address[] memory tokenAddresses,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            uint256[2] memory nameHaxIndex = subscriptionIndexByHexName[hexName];
            require(_efficientHash(bytes32(nameHaxIndex[0]), bytes32(nameHaxIndex[1])) == _efficientHash(bytes32(0), bytes32(0)),"Specified haxName is already in use");
            require(tokenAddresses[0] == address(0) && price >= 10**6 || price > 0, "Low price");
            require(tokenAddresses.length > 0, "Specify at least one token address");
            require(!mainNFT.isAddressExist(address(0), tokenAddresses) ||  tokenAddresses.length == 1, "It is unacceptable to specify a native coin and tokens");
            require(!isRegularSubscription || paymetnPeriod >= 4 hours, "Payment period cannot be less than 4 hours for regular subscription");
            if (tokenAddresses[0] != address(0) && tokenAddresses.length > 1){
                for(uint256 i = 0; i < tokenAddresses.length; i++){
                    require(mainNFT.converTokenPriceToEth(tokenAddresses[i], 10**24) > 0, "It is not possible to accept payment in one of the specified currencies");
                }
            }

            uint256 len = subscriptionsByAuthor[author].length;
            subscriptionIndexByHexName[hexName] = [author, len];
            for (uint256 i = 0; i < discountProgramm.length; i++){
                require(discountProgramm[i].amountAsPPM <= 1000, "Error in discount programm");
                discountSubscriptionsByAuthor[author][len].push(discountProgramm[i]);
            }

            participantIndex[author][len][address(this)] = participantsSubscriptionsByAuthor[author][len].length;
            participantsSubscriptionsByAuthor[author][len].push(Participant(address(this), type(uint256).max));

            Subscription memory subscription = Subscription({
                hexName: hexName,
                isActive: true,
                isRegularSubscription: isRegularSubscription,
                paymetnPeriod: paymetnPeriod,
                tokenAddresses: tokenAddresses,
                price: price
            });
            subscriptionsByAuthor[author].push(subscription);

            if (isRegularSubscription) {
                emit NewRegularSubscriptionCreated(author, hexName, tokenAddresses, price, paymetnPeriod, discountProgramm);
            } else {
                emit NewOneTimeSubscriptionCreated(author, hexName, tokenAddresses, price, discountProgramm);
            }
    }

    function changeActivityState(uint256 author, uint256 subscriptionId) public onlyAuthor(author){
        subscriptionsByAuthor[author][subscriptionId].isActive = !subscriptionsByAuthor[author][subscriptionId].isActive;
    }

    function setNewDiscountProgramm(uint256 author, uint256 subscriptionId, Discount[] memory discountProgramm) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionId].isActive, "Subscription is not active");
        uint256 len = discountSubscriptionsByAuthor[author][subscriptionId].length;
        while (len-- > 0){
            discountSubscriptionsByAuthor[author][subscriptionId].pop();
        }
        for (uint256 i = 0; i < discountProgramm.length; i++){
            require(discountProgramm[i].amountAsPPM < 1000, "Error in discount programm");
            discountSubscriptionsByAuthor[author][len].push(discountProgramm[i]);
        }
    }

    function setNewPaymetnPeriod(uint256 author, uint256 subscriptionId, uint256 paymetnPeriod) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionId].isActive, "Subscription is not active");
        require(subscriptionsByAuthor[author][subscriptionId].isRegularSubscription, "Only for regular subscription");
        require(paymetnPeriod >= 4 hours, "Payment period cannot be less than 4 hours");
        subscriptionsByAuthor[author][subscriptionId].paymetnPeriod = paymetnPeriod;
    }

    function setNewTokensAndPrice(uint256 author, uint256 subscriptionId,  address[] memory tokenAddresses, uint256 price) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionId].isActive, "Subscription is not active");
        require(tokenAddresses.length > 0, "Specify at least one token address");
        require(!mainNFT.isAddressExist(address(0), tokenAddresses) ||  tokenAddresses.length == 1, "It is unacceptable to specify a native coin and tokens");
        require(tokenAddresses[0] == address(0) && price >= 10**6 || price > 0, "Low price");
        if (tokenAddresses[0] != address(0) && tokenAddresses.length > 1){
                for(uint256 i = 0; i < tokenAddresses.length; i++){
                    require(mainNFT.converTokenPriceToEth(tokenAddresses[i], 10**24) > 0, "It is not possible to accept payment in one of the specified currencies");
                }
            }
        subscriptionsByAuthor[author][subscriptionId].tokenAddresses = tokenAddresses;
        subscriptionsByAuthor[author][subscriptionId].price = price;
    }

    function getSubscriptionsByAuthor(uint256 author) public view returns (Subscription[] memory){
        return subscriptionsByAuthor[author];
    }

    function getDiscountSubscriptionsByAuthor(uint256 author, uint256 subscriptionId) public view returns (Discount[] memory){
        return discountSubscriptionsByAuthor[author][subscriptionId];
    }

    function getPaymentSubscriptionsByAuthor(uint256 author, uint256 subscriptionId) public view returns (Payment[] memory){
        return paymentSubscriptionsByAuthor[author][subscriptionId];
    }

    function getParticipantsSubscriptionsByAuthor(uint256 author, uint256 subscriptionId) public view returns (Participant[] memory){
        return participantsSubscriptionsByAuthor[author][subscriptionId];
    }

    function getRatingSubscriptionsByAuthor(uint256 author, uint256 subscriptionId) public view returns (uint256 active, uint256 cancelled){
        Participant[] memory participants = participantsSubscriptionsByAuthor[author][subscriptionId];
        for(uint256 i = 0; i < participants.length; i++){
            if (participants[i].subscriptionEndTime >= block.timestamp){
                active++;
            } else {
                cancelled++;
            }
        }
    }

    function getTotalPaymentAmountForPeriod(
        address tokenAddress, 
        uint256 author, 
        uint256 subscriptionId, 
        uint256 periods) public view returns (uint256 amount, uint256 amountInEth){
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionId];
        Discount[] memory discount = discountSubscriptionsByAuthor[author][subscriptionId];
        uint256 maxDiscount = 0;
        if (subscription.isRegularSubscription){
            for (uint256 i = 0; i < discount.length; i++){
                if (periods >= discount[i].period && maxDiscount < discount[i].amountAsPPM){
                    maxDiscount = discount[i].amountAsPPM;
                }
            }
        }
        amount = subscription.price.mul(periods).mul(1000 - maxDiscount).div(1000);
        if (tokenAddress != address(0)) {
            amountInEth = mainNFT.converTokenPriceToEth(tokenAddress, amount);
            uint256 baseAmountInEth = mainNFT.converTokenPriceToEth(subscription.tokenAddresses[0], amount);
            amount = amountInEth > 0 && baseAmountInEth > 0 ? amount.mul(baseAmountInEth).div(amountInEth) : amount;
        } else {
            amountInEth = amount;
        }
    }

    function getSubscriptionIndexByHexName(bytes32 hexName) public view returns (uint256[2] memory){
        return subscriptionIndexByHexName[hexName];
    }
    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function subscriptionPayment(uint256 author, uint256 subscriptionId, address tokenAddress, uint256 periods) public payable{
        require(!blackListByAuthor[author][msg.sender], "You blacklisted");
        require(periods > 0, "Periods must be greater than zero");
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionId];
        require(subscription.isActive, "Subscription is not active");
        require(mainNFT.isAddressExist(tokenAddress, subscription.tokenAddresses), "The token is not suitable for payment");
        uint256 thisParticipantIndex = participantIndex[author][subscriptionId][msg.sender];
        require(thisParticipantIndex == 0 || subscription.isRegularSubscription, "You already have access to a subscription");
        (uint256 amount, uint256 amountInEth) = getTotalPaymentAmountForPeriod(tokenAddress, author, subscriptionId, periods);
        if (tokenAddress == address(0)){
            require(msg.value == amount, "Payment value does not match the price");
            _paymentEth(author, amount);
        } else {
            require(msg.value == 0, "Payment in native coin is not provided for this subscription");
            _paymentToken(msg.sender, tokenAddress, amount, author);
        }

        uint256 subscriptionEndTime = subscription.isRegularSubscription ?
            (block.timestamp).add(subscription.paymetnPeriod.mul(periods)) : type(uint256).max;
        if (thisParticipantIndex != 0){
            subscriptionEndTime = (participantsSubscriptionsByAuthor[author][subscriptionId][thisParticipantIndex].subscriptionEndTime)
                .add(subscription.paymetnPeriod.mul(periods));
            participantsSubscriptionsByAuthor[author][subscriptionId][thisParticipantIndex].subscriptionEndTime = subscriptionEndTime;
        } else {
            Participant[] storage participants = participantsSubscriptionsByAuthor[author][subscriptionId];
            participantIndex[author][subscriptionId][msg.sender] = participants.length;
            participants.push(Participant(msg.sender, subscriptionEndTime));
        }
        paymentSubscriptionsByAuthor[author][subscriptionId].push(Payment(tokenAddress, amount, amountInEth, block.timestamp));
        totalPaymentSubscriptionsByAuthoInEth[author][subscriptionId] += amountInEth;
        emit NewSubscription(msg.sender, author, subscriptionId, subscriptionEndTime, tokenAddress, amount);
    }

    function _paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        uint256 amount = value - contractFee;
        (bool success1, ) = owner().call{value: contractFee}("");
        (bool success2, ) = ownerOf(author).call{value: amount}("");
        require(success1 && success2, "fail");
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function _paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        token.transferFrom(sender, owner(), contractFee);
        uint256 amount = tokenAmount - contractFee;
        token.transferFrom(sender, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function owner() public view returns(address){
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
        (bool success, ) = owner().call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_address);
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 amount = tokenBalance;
        token.transfer(owner(), amount);
    }
    /***************Support END**************/

    receive() external payable {
        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "fail");
        emit Received(msg.sender, msg.value);
    }
}