// SPDX-License-Identifier: MIT                                                

pragma solidity ^0.8.18;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

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
    function converTokenPriceToEth(address, uint256) external view returns(uint256);
}

contract SubscriptionsTest is ReentrancyGuard {
    using SafeMath for uint256;

    IMainNFT mainNFT;    
    IUniswapV2Router02 uniswapRouter;

    struct Discount{
        uint256 period;
        uint16 amountAsPPM;
    }

    struct Payment{
        address tokenAddress;
        uint256 amount;
        uint256 amountInEth;
        uint256 paymentTime;
    }

    struct Subscription{
        bytes32 hexId;
        bool isActive;
        bool isRegularSubscription;
        uint256 paymetnPeriod;
        address tokenAddress;
        uint256 price;
    }

    struct Participant{
        address participantAddress;
        uint256 subscriptionEndTime;
    }

    mapping(address => bool) public approvedTokensForSwap;
    mapping(uint256 => mapping(address => bool)) public blackListByAuthor;
    mapping(uint256 => Subscription[]) public subscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => Discount[])) public discountSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => Participant[])) public participantsSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public participantIndex;
    mapping(bytes32 => uint256[2]) public subscriptionIndexByHexId;
    
    mapping(uint256 => mapping(uint256 => Payment[])) public paymentSubscriptionsByAuthor;
    mapping(uint256 => mapping(uint256 => uint256)) public totalPaymentSubscriptionsByAuthoInEth;

    event Received(address indexed sender, uint256 value);
    event NewOneTimeSubscriptionCreated(uint256 indexed author, bytes32 indexed hexId, address tokenAddress, uint256 price, Discount[] discounts);
    event NewRegularSubscriptionCreated(uint256 indexed author, bytes32 indexed hexId, address tokenAddress, uint256 price, uint256 paymetnPeriod, Discount[] discounts);
    event NewSubscription(address indexed participant, uint256 indexed author, uint256 indexed subscriptionIndex, uint256 subscriptionEndTime, address tokenAddress, uint256 amount);

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

    constructor(address mainNFTAddress, address[] memory tokensForSwap) {
        mainNFT = IMainNFT(mainNFTAddress);
        mainNFT.setVerfiedContracts(true, address(this));

        address _uniswapRouterAddress = mainNFT.getUniswapRouterAddress();
        uniswapRouter = IUniswapV2Router02(_uniswapRouterAddress);

        approveCustomTokenForSwap(uniswapRouter.WETH());
        for (uint256 i = 0; i < tokensForSwap.length; i++){
            approveCustomTokenForSwap(tokensForSwap[i]);
        }
    }

    /***************Author options BGN***************/
    function addToBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = true;
    }

    function removeBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
    }

    function createNewSubscriptionByEth(
        bytes32 hexId,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            createNewSubscriptionByToken(hexId, author, isRegularSubscription, paymetnPeriod, address(0), price, discountProgramm);
    }

    function createNewSubscriptionByToken(
        bytes32 hexId,
        uint256 author,
        bool isRegularSubscription,
        uint256 paymetnPeriod,
        address tokenAddress,
        uint256 price,
        Discount[] memory discountProgramm) public onlyAuthor(author){
            uint256[2] memory arrayHexId = subscriptionIndexByHexId[hexId];
            require(_efficientHash(bytes32(arrayHexId[0]), bytes32(arrayHexId[1])) == _efficientHash(bytes32(0), bytes32(0)),"Specified hexId is already in use");
            require(tokenAddress == address(0) && price >= 10**6 || price > 0, "Low price");
            require(!isRegularSubscription || paymetnPeriod >= 4 hours, "Payment period cannot be less than 4 hours for regular subscription");
            require(tokenAddress == address(0) || mainNFT.converTokenPriceToEth(tokenAddress, 10**24) > 0, "It is not possible to accept payment");

            uint256 len = subscriptionsByAuthor[author].length;
            subscriptionIndexByHexId[hexId] = [author, len];
            for (uint256 i = 0; i < discountProgramm.length; i++){
                require(discountProgramm[i].amountAsPPM <= 1000, "Error in discount programm");
                discountSubscriptionsByAuthor[author][len].push(discountProgramm[i]);
            }

            participantIndex[author][len][address(this)] = participantsSubscriptionsByAuthor[author][len].length;
            participantsSubscriptionsByAuthor[author][len].push(Participant(address(this), type(uint256).max));

            Subscription memory subscription = Subscription({
                hexId: hexId,
                isActive: true,
                isRegularSubscription: isRegularSubscription,
                paymetnPeriod: paymetnPeriod,
                tokenAddress: tokenAddress,
                price: price
            });
            subscriptionsByAuthor[author].push(subscription);

            if (isRegularSubscription) {
                emit NewRegularSubscriptionCreated(author, hexId, tokenAddress, price, paymetnPeriod, discountProgramm);
            } else {
                emit NewOneTimeSubscriptionCreated(author, hexId, tokenAddress, price, discountProgramm);
            }
    }

    function changeActivityState(uint256 author, uint256 subscriptionIndex) public onlyAuthor(author){
        subscriptionsByAuthor[author][subscriptionIndex].isActive = !subscriptionsByAuthor[author][subscriptionIndex].isActive;
    }

    function setNewDiscountProgramm(uint256 author, uint256 subscriptionIndex, Discount[] memory discountProgramm) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionIndex].isActive, "Subscription is not active");
        uint256 len = discountSubscriptionsByAuthor[author][subscriptionIndex].length;
        while (len-- > 0){
            discountSubscriptionsByAuthor[author][subscriptionIndex].pop();
        }
        for (uint256 i = 0; i < discountProgramm.length; i++){
            require(discountProgramm[i].amountAsPPM < 1000, "Error in discount programm");
            discountSubscriptionsByAuthor[author][len].push(discountProgramm[i]);
        }
    }

    function setNewPaymetnPeriod(uint256 author, uint256 subscriptionIndex, uint256 paymetnPeriod) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionIndex].isActive, "Subscription is not active");
        require(subscriptionsByAuthor[author][subscriptionIndex].isRegularSubscription, "Only for regular subscription");
        require(paymetnPeriod >= 4 hours, "Payment period cannot be less than 4 hours");
        subscriptionsByAuthor[author][subscriptionIndex].paymetnPeriod = paymetnPeriod;
    }

    function setNewTokensAndPrice(uint256 author, uint256 subscriptionIndex, address tokenAddress, uint256 price) public onlyAuthor(author){
        require(subscriptionsByAuthor[author][subscriptionIndex].isActive, "Subscription is not active");
        require(tokenAddress == address(0) && price >= 10**6 || price > 0, "Low price");
        require(tokenAddress == address(0) || mainNFT.converTokenPriceToEth(tokenAddress, 10**24) > 0, "The token is not suitable for payment");

        subscriptionsByAuthor[author][subscriptionIndex].tokenAddress = tokenAddress;
        subscriptionsByAuthor[author][subscriptionIndex].price = price;
    }

    function getSubscriptionsByAuthor(uint256 author) public view returns (Subscription[] memory){
        return subscriptionsByAuthor[author];
    }

    function getDiscountSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (Discount[] memory){
        return discountSubscriptionsByAuthor[author][subscriptionIndex];
    }

    function getPaymentSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (Payment[] memory){
        return paymentSubscriptionsByAuthor[author][subscriptionIndex];
    }

    function getParticipantsSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (Participant[] memory){
        return participantsSubscriptionsByAuthor[author][subscriptionIndex];
    }

    function getRatingSubscriptionsByAuthor(uint256 author, uint256 subscriptionIndex) public view returns (uint256 active, uint256 cancelled){
        Participant[] memory participants = participantsSubscriptionsByAuthor[author][subscriptionIndex];
        for(uint256 i = 0; i < participants.length; i++){
            if (participants[i].subscriptionEndTime >= block.timestamp){
                active++;
            } else {
                cancelled++;
            }
        }
    }

    function getTotalPaymentAmountForPeriod( 
        uint256 author, 
        uint256 subscriptionIndex, 
        uint256 periods) public view returns (uint256 amountInToken, uint256 amountInEth){
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionIndex];
        Discount[] memory discount = discountSubscriptionsByAuthor[author][subscriptionIndex];
        uint256 maxDiscount = 0;
        if (subscription.isRegularSubscription){
            for (uint256 i = 0; i < discount.length; i++){
                if (periods >= discount[i].period && maxDiscount < discount[i].amountAsPPM){
                    maxDiscount = discount[i].amountAsPPM;
                }
            }
        }
        amountInToken = subscription.price.mul(periods).mul(1000 - maxDiscount).div(1000);
        amountInEth = subscription.tokenAddress != address(0) ? amountInToken : mainNFT.converTokenPriceToEth(subscription.tokenAddress, amountInToken);
    }

    function getSubscriptionIndexByHexId(bytes32 hexId) public view returns (uint256[2] memory){
        return subscriptionIndexByHexId[hexId];
    }
    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function subscriptionPayment(uint256 author, uint256 subscriptionIndex, address participantSelectedTokenAddress, uint256 periods) public payable{
        require(!blackListByAuthor[author][msg.sender], "You blacklisted");
        require(periods > 0, "Periods must be greater than zero");
        Subscription memory subscription = subscriptionsByAuthor[author][subscriptionIndex];
        require(subscription.isActive, "Subscription is not active");
        require(mainNFT.converTokenPriceToEth(participantSelectedTokenAddress, 10**24) > 0, "The token is not suitable for payment");
        uint256 thisParticipantIndex = participantIndex[author][subscriptionIndex][msg.sender];
        require(thisParticipantIndex == 0 || subscription.isRegularSubscription, "You already have access to a subscription");
        (uint256 amountInToken, uint256 amountInEth) = getTotalPaymentAmountForPeriod(author, subscriptionIndex, periods);
        if (subscription.tokenAddress == address(0)){
            require(msg.value == amountInToken, "Payment value does not match the price");
            _paymentEth(author, amountInToken);
        } else {
            require(msg.value == 0, "Payment in native coin is not provided for this subscription");
            if (participantSelectedTokenAddress != subscription.tokenAddress){
                _swapTokenAndPay(msg.sender, participantSelectedTokenAddress, subscription.tokenAddress, amountInToken, author);
            } else {
                _paymentToken(msg.sender, participantSelectedTokenAddress, amountInToken, author);
            }
        }

        uint256 subscriptionEndTime = subscription.isRegularSubscription ?
            (block.timestamp).add(subscription.paymetnPeriod.mul(periods)) : type(uint256).max;
        if (thisParticipantIndex != 0){
            subscriptionEndTime = (participantsSubscriptionsByAuthor[author][subscriptionIndex][thisParticipantIndex].subscriptionEndTime)
                .add(subscription.paymetnPeriod.mul(periods));
            participantsSubscriptionsByAuthor[author][subscriptionIndex][thisParticipantIndex].subscriptionEndTime = subscriptionEndTime;
        } else {
            Participant[] storage participants = participantsSubscriptionsByAuthor[author][subscriptionIndex];
            participantIndex[author][subscriptionIndex][msg.sender] = participants.length;
            participants.push(Participant(msg.sender, subscriptionEndTime));
        }
        paymentSubscriptionsByAuthor[author][subscriptionIndex].push(Payment(subscription.tokenAddress, amountInToken, amountInEth, block.timestamp));
        totalPaymentSubscriptionsByAuthoInEth[author][subscriptionIndex] += amountInEth;
        emit NewSubscription(msg.sender, author, subscriptionIndex, subscriptionEndTime, subscription.tokenAddress, amountInToken);
    }

    function _paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        uint256 amount = value - contractFee;
        (bool success1, ) = commissionCollector().call{value: contractFee}("");
        (bool success2, ) = ownerOf(author).call{value: amount}("");
        require(success1 && success2, "fail");
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function _swapTokenAndPay(address sender, address selectedTokenAddress, address tokenAddress, uint256 tokenAmount, uint256 author) internal {
        require(approvedTokensForSwap[selectedTokenAddress], "The token is not approved for swap");
        address[] memory path = new address[](0);  
        if (selectedTokenAddress == uniswapRouter.WETH() || tokenAddress == uniswapRouter.WETH()){
            path = new address[](2);
            path[0] = selectedTokenAddress;
            path[1] = tokenAddress;
        } else {
            path = new address[](3);
            path[0] = selectedTokenAddress;
            path[1] = uniswapRouter.WETH();
            path[2] = tokenAddress;
        }
        uint256[] memory amounts = uniswapRouter.getAmountsIn(tokenAmount, path);
        uint256 debitedAmount = amounts[0].mul(101).div(100);
        require(debitedAmount > 0, "Payment fail");

        IERC20 selectedToken = IERC20(selectedTokenAddress);
        selectedToken.transferFrom(sender, address(this), debitedAmount);
        uniswapRouter.swapTokensForExactTokens(tokenAmount, debitedAmount, path, address(this), (block.timestamp).add(3600));

        _paymentTokenFromContract(tokenAddress, tokenAmount, author);
        _withdrawTokens(selectedTokenAddress);

        selectedToken.approve(address(uniswapRouter), type(uint256).max);
    }

    function _paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        token.transferFrom(sender, commissionCollector(), contractFee);
        uint256 amount = tokenAmount.sub(contractFee);
        token.transferFrom(sender, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }

    function _paymentTokenFromContract(address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        token.transfer(commissionCollector(), contractFee);
        uint256 amount = tokenAmount.sub(contractFee);
        token.transfer(ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function owner() public view returns(address){
        return mainNFT.owner();
    }

    function commissionCollector() public view returns(address){
        return mainNFT.commissionCollector();
    }

    function ownerOf(uint256 author) public view returns (address){
        return mainNFT.ownerOf(author);
    }

    function _setNewRouter(address _uniswapRouterAddress) internal onlyOwner{
        uniswapRouter = IUniswapV2Router02(_uniswapRouterAddress);
    }

    function approveCustomTokenForSwap(address tokenAddress) public{
        require(mainNFT.converTokenPriceToEth(tokenAddress, 10**18) > 0, "Token is not available to swap, it is not supported by DEX");
        IERC20 token = IERC20(tokenAddress);
        token.approve(address(uniswapRouter), type(uint256).max);
        approvedTokensForSwap[tokenAddress] = true;
    }

    function setIMainNFT(address mainNFTAddress) external onlyOwner{
        mainNFT = IMainNFT(mainNFTAddress);
        mainNFT.setVerfiedContracts(true, address(this));
        _setNewRouter(mainNFT.getUniswapRouterAddress());
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        (bool success, ) = commissionCollector().call{value: amount}("");
        require(success, "fail");
    }

    function _withdrawTokens(address _address) internal {
        IERC20 token = IERC20(_address);
        uint256 amount = token.balanceOf(address(this));
        token.transfer(commissionCollector(), amount);
    }

    function withdrawTokens(address _address) public onlyOwner nonReentrant {
        _withdrawTokens(_address);
    }
    /***************Support END**************/

    receive() external payable {
        (bool success, ) = commissionCollector().call{value: msg.value}("");
        require(success, "fail");
        emit Received(msg.sender, msg.value);
    }
}