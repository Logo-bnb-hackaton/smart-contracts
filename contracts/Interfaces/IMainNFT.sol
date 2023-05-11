// SPDX-License-Identifier: GPL-2.0-or-later                                              
pragma solidity ^0.8.0;

interface IMainNFT {
    function getUniswapHelperAddress() external view returns (address);
    function getPriceFeedChainlinkAddress() external view returns (address);
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