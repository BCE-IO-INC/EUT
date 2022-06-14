// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBCEMusicSettings.sol";

contract BCEMusicSettings is Ownable, IBCEMusicSettings {
    uint private _auctionBidLimit;
    uint private _ownerFeePercentForAuction;
    uint private _ownerFeePercentForSecondaryMarket;

    constructor() Ownable() {
        _auctionBidLimit = 200;
        _ownerFeePercentForAuction = 10;
        _ownerFeePercentForSecondaryMarket = 5;
    }
    function setAuctionBidLimit(uint l) external onlyOwner {
        require(l>0 && l<10000, "bad limit.");
        _auctionBidLimit = l;
    }
    function setOwnerFeePercentForAuction(uint p) external onlyOwner {
        require(p>=0 && p<=100, "bad percentage.");
        _ownerFeePercentForAuction = p;
    }
    function setOwnerFeePercentForSecondaryMarket(uint p) external onlyOwner {
        require(p>=0 && p<=100, "bad percentage.");
        _ownerFeePercentForSecondaryMarket = p;
    }
    function auctionBidLimit() external view override returns (uint) {
        return _auctionBidLimit;
    }
    function ownerFeePercentForAuction() external view override returns (uint) {
        return _ownerFeePercentForAuction;
    }
    function ownerFeePercentForSecondaryMarket() external view override returns (uint) {
        return _ownerFeePercentForSecondaryMarket;
    }
}