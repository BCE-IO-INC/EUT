// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";

//The current design is that BCEMusic will be deployed in various instances,
//each instance holding diamond/golden NFTs for one single song only, and therefore
//we use this BCEMusicMarket as a registry to hold the information for all
//deployed instances of BCEMusic.

//An alternative design where BCEMusic holds all the NFTs for all songs is 
//technically feasible, but for now we use this design to make it easier to 
//isolate each song (in order to diversity attack and bug risks).

//If we try to create BCEMusic within a method here, solidity will complain
//that the contract size is too big for deployment onto mainnet, therefore
//this contract is simply a name registry.

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