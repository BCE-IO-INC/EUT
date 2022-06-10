// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

//If we try to create BCEMusic within a method here, solidity will complain
//that the contract size is too big for deployment onto mainnet, therefore
//this contract is simply a registry.

contract BCEMusicMarket is Ownable {
    mapping (string => address) private _musicNFTs;
    string[] private _musicNames;

    constructor() Ownable() {
    }

    function nftByName(string calldata name) external view returns(address) {
        return _musicNFTs[name];
    }
    function allMusicNames() external view returns(string[] memory) {
        return _musicNames;
    }
    function registerNFT(string calldata name, address addr) external onlyOwner {
        require(_musicNFTs[name] == address(0), "music NFT already exists");
        _musicNames.push(name);
        _musicNFTs[name] = addr;
    }
}