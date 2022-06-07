// SPDX-License-Identifier: MIT

import "./EutLibrary.sol";
import "./ERC721.sol";

// EutMusic is authored by Eut.io
// Holds who owns what
// Contract.balance Holds CO's profit.

pragma solidity >=0.6.0 <0.8.0;
/**
 * @title EutMusic contract
 * @dev Extends ERC721 Non-Fungible Token Standard basic implementation
 */
contract EutMusic is ERC721, Ownable {
    using SafeMath for uint256;

    string public constant musicTokenSymbol = "ETH";
    bool public marketIsActive = false;
    mapping (uint => uint) public _tokenPrices;

    // Events
    event newTokenMinted (uint indexed _tokenId);
    event newOrderGenerated (uint indexed _tokenId, uint indexed price);

    constructor(string memory _name, uint256 saleStart) ERC721(_name, musicTokenSymbol) {
        flipMarketState();
    }

    // Withdraw all money in this account to the account owner. 
    function withdraw() public onlyOwner {
        uint balance = address(this).balance;
        msg.sender.transfer(balance);
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        _setBaseURI(baseURI);
    }

    function flipMarketState() public onlyOwner {
        marketIsActive = !marketIsActive;
    }

    // Mint new NFT (by contract owner only).
    function mintNewToken() public onlyOwner payable {
        require(marketIsActive, "Market is not active yet.");
        uint tokenId = totalSupply(); // Current watermark
        _safeMint(msg.sender, tokenId);
        _tokenPrices[tokenId] = 0; // Not for sale until otherwise.
        emit newTokenMinted(tokenId);
    }

    function getEutMusicUrl(uint256 tokenId) public view returns (string memory)  {
        return tokenURI(tokenId);
    }

    function getOwnerByTokenId(uint256 tokenId) public view returns (address) {
        return ownerOf(tokenId);
    }

    function getPriceByTokenId(uint tokenId) public view returns (uint) {
        return _tokenPrices[tokenId];
    }

    // EUT SPECIFIC Transaction Functions
    // Airdrop the NFT. Applies only to the music whose owner is the contract owner.  
    function airDropInitialOwner(address _to, uint256 tokenId) public onlyOwner {
        require(marketIsActive, "Market is not active yet.");
        require(_exists(tokenId), "EutMusic: nonexistent token.");
        require(msg.sender ==getOwnerByTokenId(tokenId), "EutMusic: CO does not own this token");
        _transfer(msg.sender, _to, tokenId);
    }

    function placeSecondaryMarketOrder(uint tokenId, uint price) public {
        require(marketIsActive, "Market is not active yet.");
        require(_exists(tokenId), "EutMusic: nonexistent token.");
        require(msg.sender == getOwnerByTokenId(tokenId), "Only the owner could sell.");
        _tokenPrices[tokenId] = price;
        emit newOrderGenerated(tokenId, price);
    }

    function updateOrderPriceByContractOwner(uint tokenId, uint price) public onlyOwner {
        require(marketIsActive, "Market is not active yet.");
        require(_exists(tokenId), "EutMusic: nonexistent token.");
        _tokenPrices[tokenId] = price;
    }

    function cancelOrderByContractOwner(uint tokenId) public onlyOwner {
        require(marketIsActive, "Market is not active yet.");
        require(_exists(tokenId), "EutMusic: nonexistent token.");
        _tokenPrices[tokenId] = 0;
    }    

    // Fulfillment of a secondary market order. 
    function acceptSecondaryMarketOrder(uint tokenId) public payable {
        require(marketIsActive, "Market is not active yet.");
        address buyer = msg.sender;
        address seller = getOwnerByTokenId(tokenId);
        require(_exists(tokenId), "EutMusic: nonexistent token.");
        require(_tokenPrices[tokenId] != 0, "NFT not for sale.");
        require(msg.value >= _tokenPrices[tokenId], "Price not high enough.");
        _transfer(seller, buyer, tokenId);
        _tokenPrices[tokenId] = 0;
        payable(seller).transfer(msg.value);
    }
}