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
}

contract Sessions is ReentrancyGuard {
    using SafeMath for uint256;

    address verifierProvider;
    IMainNFT mainNFT;

    enum Types {
        notModerated,
        moderated
    }

    struct Participants {
        address[] confirmed;
        address[] notConfirmed;
        address[] rejected;
    }

    struct Rating {
        uint256 like;
        uint256 dislike;
    }

    struct Session {
        address tokenAddress;
        uint256 price;
        uint256 expirationTime;
        uint256 maxParticipants;
        string name;
        Types typeOf;
        Participants participants;
        Rating rating;
    }

    mapping(uint256 => mapping(address => bool)) public whiteListByAuthor;
    mapping(uint256 => mapping(address => bool)) public blackListByAuthor;
    mapping(uint256 => Session[]) public sessionByAuthor;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public participantVoted;
    mapping(uint256 => mapping(uint256 => mapping(address => string))) public invitationToTg;
    mapping(address => uint256) internal blockedForWithdraw;

    event Received(address indexed sender, uint256 value);
    event NewSessionCreated(uint256 indexed author, string name, address token, uint256 price, uint256 expirationTime, uint256 maxParticipants, Types typeOf);
    event AwaitingConfirmation(address indexed participant, uint256 indexed author, uint256 indexed sessionId);
    event PurchaseConfirmed(address indexed participant, uint256 indexed author, uint256 indexed sessionId);
    event PurchaseRejected(address indexed participant, uint256 indexed author, uint256 indexed sessionId);
    event PurchaseCanceled(address indexed participant, uint256 indexed author, uint256 indexed sessionId);
    event NewVote(bool isLike, address indexed participant, uint256 indexed author, uint256 indexed sessionId);
    
    modifier onlyOwner() {
        require(owner() == msg.sender, "Only owner");
        _;
    }

    modifier onlyAuthor(uint256 author) {
        require(mainNFT.onlyAuthor(msg.sender, author), "Only for Author");
        _;
    }

    modifier onlyVerifierProvider(){
        require(verifierProvider == msg.sender, "Only verifier provider");
        _;
    }

    modifier supportsERC20(address _address){
        require(
            _address == address(0) || IERC20(_address).totalSupply() > 0 && IERC20(_address).allowance(_address, _address) >= 0,
            "Is not ERC20"
        );
        _;
    }
    
    modifier sessionIsOpenForSender(uint256 author, uint256 sessionId){
        require(!blackListByAuthor[author][msg.sender], "You blacklisted");
        Session memory session = sessionByAuthor[author][sessionId];
        require(session.expirationTime > block.timestamp && session.participants.confirmed.length < session.maxParticipants, "Session is closed");
        Participants memory participants = session.participants;
        require(!mainNFT.isAddressExist(msg.sender, participants.rejected), "You denied");
        require(!mainNFT.isAddressExist(msg.sender, participants.notConfirmed), "Expect decision on your candidacy");
        require(!mainNFT.isAddressExist(msg.sender, participants.confirmed), "You already on list");
        _;
    }

    constructor(address _mainNFTAddress, address _verifierProvider) {
        mainNFT = IMainNFT(_mainNFTAddress);
        setVerifierProvider(_verifierProvider);
    }

    /***************Author options BGN***************/
    function createNewSessionByEth(
        uint256 author, 
        uint256 price, 
        uint256 expirationTime, 
        uint256 maxParticipants, 
        Types typeOf, 
        string memory name) public onlyAuthor(author){
            require(price >= 10**6, "Low price");
            createNewSessionByToken(author, address(0), price, expirationTime, maxParticipants, typeOf, name);
        }

    function createNewSessionByToken(
        uint256 author, 
        address tokenAddress, 
        uint256 price, 
        uint256 expirationTime, 
        uint256 maxParticipants, 
        Types typeOf, 
        string memory name) supportsERC20(tokenAddress) public onlyAuthor(author){
            require(price > 0, "Low price");
            Rating memory rating = Rating(0, 0);  
            Participants memory participants = Participants(
                new address[](0),
                new address[](0),
                new address[](0)
            );        
            Session memory session = Session ({
                tokenAddress: tokenAddress,
                price: price,
                expirationTime: expirationTime,
                maxParticipants: maxParticipants,
                name: name,
                typeOf: typeOf,
                participants: participants,
                rating: rating
            });
            sessionByAuthor[author].push(session);
            emit NewSessionCreated(author, name, tokenAddress, price, expirationTime, maxParticipants, typeOf);
    }

    function addToWhiteList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
        whiteListByAuthor[author][user] = true;
    }

    function removeWhiteList(address user, uint256 author) public onlyAuthor(author){
        whiteListByAuthor[author][user] = false;
    }

    function addToBlackList(address user, uint256 author) public onlyAuthor(author){
        whiteListByAuthor[author][user] = false;
        blackListByAuthor[author][user] = true;
    }

    function removeBlackList(address user, uint256 author) public onlyAuthor(author){
        blackListByAuthor[author][user] = false;
    }

    function confirmParticipants(address participant, uint256 author, uint256 sessionId) public onlyAuthor(author) returns(bool) {
        Session storage session = sessionByAuthor[author][sessionId];
        Participants storage participants = session.participants;
        require(mainNFT.isAddressExist(participant, participants.notConfirmed), "Is denied");
        address[] storage notConfirmed = participants.notConfirmed;
        for (uint i = 0; i < notConfirmed.length; i++) {
            if (notConfirmed[i] == participant) {
                notConfirmed[i] = notConfirmed[notConfirmed.length - 1];
                notConfirmed.pop();
                participants.confirmed.push(participant);
                unblockAndPay(session.tokenAddress, session.price, author);
                emit PurchaseConfirmed(participant, author, sessionId);
                return true;
            }
        }
        return false;
    }

    function unconfirmParticipants(address participant, uint256 author, uint256 sessionId) public onlyAuthor(author) returns(bool) {
        Session storage session = sessionByAuthor[author][sessionId];
        Participants storage participants = session.participants;
        require(mainNFT.isAddressExist(participant, participants.notConfirmed), "Is denied");
        address[] storage notConfirmed = participants.notConfirmed;
        for (uint i = 0; i < notConfirmed.length; i++) {
            if (notConfirmed[i] == participant) {
                notConfirmed[i] = notConfirmed[notConfirmed.length - 1];
                notConfirmed.pop();
                participants.rejected.push(participant);
                unblockAndReject(participant, session.tokenAddress, session.price);
                emit PurchaseRejected(participant, author, sessionId);
                return true;
            }
        }
        return false;
    }

    function unblockAndPay(address tokenAddress, uint256 tokenAmount, uint256 author) internal {
        if (tokenAddress == address(0)){
            paymentEth(author, tokenAmount);
        } else {
            paymentToken(address(this), tokenAddress, tokenAmount, author);
        }
        blockedForWithdraw[tokenAddress] -= tokenAmount;
    }

    function unblockAndReject(address participant, address tokenAddress, uint256 tokenAmount) internal nonReentrant {
        if (tokenAddress == address(0)){
            (bool success, ) = participant.call{value: tokenAmount}("");
            require(success, "fail");
        } else {
            IERC20 token = IERC20(tokenAddress);
            uint256 contractBalance = token.balanceOf(address(this));
            if (contractBalance < tokenAmount){
                tokenAmount = contractBalance;
            }
            token.transfer(participant, tokenAmount);
        }
        blockedForWithdraw[tokenAddress] -= tokenAmount;
    }

    function getAllSessionsByAuthor(uint256 author) public view returns (Session[] memory){
        return sessionByAuthor[author];
    }

    /***************Author options END***************/

    /***************User interfaces BGN***************/
    function paymentEth(uint256 author, uint256 value) internal nonReentrant {
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, value);
        uint256 amount = value - contractFee;
        (bool success1, ) = address(mainNFT).call{value: contractFee}("");
        (bool success2, ) = ownerOf(author).call{value: amount}("");
        require(success1 && success2, "fail");
        mainNFT.addAuthorsRating(address(0), value, author);
    }

    function paymentToken(address sender, address tokenAddress, uint256 tokenAmount, uint256 author) internal nonReentrant {
        IERC20 token = IERC20(tokenAddress);
        uint256 contractFee = mainNFT.contractFeeForAuthor(author, tokenAmount);
        token.transferFrom(sender, address(mainNFT), contractFee);
        uint256 amount = tokenAmount - contractFee;
        token.transferFrom(sender, ownerOf(author), amount);
        mainNFT.addAuthorsRating(tokenAddress, tokenAmount, author);
    }

    // Вспомогательная функция блокировки активов неподтверждённых участников
    function blockTokens(address tokenAddress, uint256 tokenAmount) internal nonReentrant {
        if (tokenAddress != address(0)){
            IERC20 token = IERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), tokenAmount);
        }
        blockedForWithdraw[tokenAddress] += tokenAmount;
    }

    // Функция покупки билета на сессию автора
    function buyTicketForSession(uint256 author, uint256 sessionId) public sessionIsOpenForSender(author, sessionId) payable{
        Session storage session = sessionByAuthor[author][sessionId];
        Participants storage participants = session.participants;
        address tokenAddress = session.tokenAddress;
        uint256 price = session.price;
        require(tokenAddress == address(0) && price == msg.value || tokenAddress != address(0), "Error value");

        if (whiteListByAuthor[author][msg.sender] || session.typeOf == Types.notModerated){
            if (tokenAddress == address(0)){
                paymentEth(author, msg.value);
            } else {
                paymentToken(msg.sender, tokenAddress, price, author);
            }
            participants.confirmed.push(msg.sender);
            emit PurchaseConfirmed(msg.sender, author, sessionId);
        } else {
            blockTokens(tokenAddress, price);
            participants.notConfirmed.push(msg.sender);
            emit AwaitingConfirmation(msg.sender, author, sessionId);
        }
    }

    function cancelByParticipant(uint256 author, uint256 sessionId) public returns(bool) {
        Session storage session = sessionByAuthor[author][sessionId];
        Participants storage participants = session.participants;
        require(mainNFT.isAddressExist(msg.sender, participants.notConfirmed), "You are not in lists");
        require(!mainNFT.isAddressExist(msg.sender, participants.confirmed), "Contact author to cancel");
        address[] storage notConfirmed = participants.notConfirmed;
        for (uint i = 0; i < notConfirmed.length; i++) {
            if (notConfirmed[i] == msg.sender) {
                notConfirmed[i] = notConfirmed[notConfirmed.length - 1];
                notConfirmed.pop();
                unblockAndReject(msg.sender, session.tokenAddress, session.price);
                emit PurchaseCanceled(msg.sender, author, sessionId);
                return true;
            }
        }
        return false;
    }

    function voteForSession(bool like, uint256 author, uint256 sessionId) public {
        Session storage session = sessionByAuthor[author][sessionId];
        require(session.expirationTime < block.timestamp, "Session not closed");
        Participants memory participants = session.participants;
        require(mainNFT.isAddressExist(msg.sender, participants.confirmed), "You arent in lists");
        require(!participantVoted[author][sessionId][msg.sender], "Your already voted");
        participantVoted[author][sessionId][msg.sender] = true;
        Rating storage rating = session.rating;
        if (like) {
            rating.like += 1;
        } else {
            rating.dislike += 1;
        }
        emit NewVote(like, msg.sender, author, sessionId);
    }
    /***************User interfaces END***************/

    /***************Support BGN***************/
    function setInvitationToTg(uint256 author, uint256 sessionId, address participant, string memory invitation) public onlyVerifierProvider{
        invitationToTg[author][sessionId][participant] = invitation;
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

    function setVerifierProvider(address _verifierProvider) public onlyOwner{
        verifierProvider = _verifierProvider;
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 amount = address(this).balance;
        (bool success, ) = address(mainNFT).call{value: amount}("");
        require(success, "fail");
    }

    function withdrawTokens(address _address) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_address);
        uint256 tokenBalance = token.balanceOf(address(this));
        uint256 amount = tokenBalance;
        token.transfer(address(mainNFT), amount);
    }
    /***************Support END**************/

    receive() external payable {
        (bool success, ) = address(mainNFT).call{value: msg.value}("");
        require(success, "fail");
        emit Received(msg.sender, msg.value);
    }
}