// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BCEMusicMarket is ERC1155, Ownable, ReentrancyGuard {

    using Counters for Counters.Counter;
    
    Counters.Counter private _tokenIds;
    Counters.Counter private _orderIds;

    uint public constant DIAMOND_TOKEN_AMOUNT = 1;
    uint public constant GOLDEN_TOKEN_AMOUNT = 499;

    error InsufficientNFT(uint ownedAmount, uint requiredAmount);
    error InsufficientBalance(uint paid, uint price);

    event RefundExtraPayment(uint paid, uint price, uint refund);

    struct MarketOrder {
        uint tokenId;
        uint amount;
        uint price;
        address payable seller;
        address payable owner;
        bool sold;
    }

    mapping (uint => MarketOrder) private idToMarketOrder;
    // The two addresses can be different. operator is responsible for settling secondary market orders. 
    address payable operator;
    address payable contractOwner;

    constructor(string memory uri) ERC1155(uri) {
        contractOwner = payable(msg.sender);
        operator = payable(msg.sender);
    }

    // Mint new NFT (by contract owner only). Diamond token and golden token use different (consecutive token IDs).
    function mintNewToken() public onlyOwner {
        uint tokenIdDiamond = _tokenIds.current(); // Current watermark
        _tokenIds.increment();
        _mint(msg.sender, tokenIdDiamond, DIAMOND_TOKEN_AMOUNT, "");
        uint tokenIdGolden = _tokenIds.current();
        _tokenIds.increment(); 
        _mint(msg.sender, tokenIdGolden, GOLDEN_TOKEN_AMOUNT, ""); 
    }

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) public onlyOwner {
        if (balanceOf(msg.sender, tokenId) < amount){
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: amount
                });
        }
        safeTransferFrom(msg.sender, receiver, tokenId, amount, "");
    }

    function createSecondaryMarketOrder(uint tokenId, uint amount, uint totalPrice) public nonReentrant {
        require(tokenId < _tokenIds.current(), "Invalid token id.");
        if (balanceOf(msg.sender, tokenId) < amount){
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: amount
                });
        }
        uint orderId = _orderIds.current();
        _orderIds.increment();
        idToMarketOrder[orderId] = MarketOrder(
            tokenId,
            amount,
            totalPrice,
            payable(msg.sender),
            operator,
            false
        );
        _safeTransferFrom(msg.sender, operator, tokenId, amount, "");
    }

    function accpetSecondaryMarketOrder(uint orderId) public payable nonReentrant {
        require (orderId < _orderIds.current(), "Invalid order id.");
        // Not sure if variable order should be of memory type.
        MarketOrder memory order = idToMarketOrder[orderId];
        require(!order.sold, "This order has been sold.");
        if (msg.value < order.price){
            revert InsufficientBalance({
                paid: msg.value,
                price: order.price
            });
        }
        order.seller.transfer(order.price);
        if (msg.value > order.price) {
            payable(msg.sender).transfer(msg.value - order.price);
            emit RefundExtraPayment(
                msg.value,
                order.price,
                msg.value - order.price
            );
        }
        _safeTransferFrom(operator, msg.sender, order.tokenId, order.amount, "");
        idToMarketOrder[orderId].sold = true;
        idToMarketOrder[orderId].owner = payable(msg.sender);
    }
}
