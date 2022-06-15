// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBCEMusicSettings.sol";

contract BCEMusicSettings is Ownable, IBCEMusicSettings {
    uint private _ownerFeePercentForAuction;
    uint private _ownerFeePercentForSecondaryMarket;

    constructor() Ownable() {
        _ownerFeePercentForAuction = 10;
        _ownerFeePercentForSecondaryMarket = 5;
    }
    function setOwnerFeePercentForAuction(uint p) external onlyOwner {
        require(p>=0 && p<=100, "bad percentage.");
        _ownerFeePercentForAuction = p;
    }
    function setOwnerFeePercentForSecondaryMarket(uint p) external onlyOwner {
        require(p>=0 && p<=100, "bad percentage.");
        _ownerFeePercentForSecondaryMarket = p;
    }
    function ownerFeePercentForAuction() external view override returns (uint) {
        return _ownerFeePercentForAuction;
    }
    function ownerFeePercentForSecondaryMarket() external view override returns (uint) {
        return _ownerFeePercentForSecondaryMarket;
    }
}