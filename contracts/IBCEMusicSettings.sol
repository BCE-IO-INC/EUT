// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBCEMusicSettings {
    function ownerFeePercentForAuction() external view returns (uint8);
    function ownerFeePercentForSecondaryMarket() external view returns (uint8);
}