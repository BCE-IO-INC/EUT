// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IBCEMusic {
    error InsufficientNFT(uint ownedAmount, uint requiredAmount);
    error InsufficientBalance(uint paid, uint price);

    struct Offer {
        uint tokenId;
        uint amount;
        uint256 totalPrice;
        address seller;
        uint256 nextOffer; //this is a linked-list kind of structure
        uint256 prevOffer;
    }

    event OfferCreated(uint256 offerId, Offer offer);
    event OfferFilled(uint256 offerId, Offer offer);
    event OfferWithdrawn(uint256 offerId, Offer offer);

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) external;
    function offer(uint tokenId, uint amount, uint256 totalPrice) external;
    function acceptOffer(uint256 offerId) external payable;
    function withdrawOffer(uint256 offerId) external;
}
