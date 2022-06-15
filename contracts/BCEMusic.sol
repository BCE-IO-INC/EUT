// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IBCEMusic.sol";
import "./IBCEMusicSettings.sol";
import "./BCEMusicAuction.sol";
import "./BCEMusicOffer.sol";

contract BCEMusic is ERC1155, Ownable, ReentrancyGuard, IBCEMusic {

    uint public constant DIAMOND_TOKEN_AMOUNT = 1;
    uint public constant GOLDEN_TOKEN_AMOUNT = 499;

    uint public constant DIAMOND_TOKEN_ID = 1;
    uint public constant GOLDEN_TOKEN_ID = 2;

    bytes private constant EMPTY_BYTES = "";

    address private _settingsAddr;

    mapping (uint => OutstandingAuctions) private _outstandingAuctions;
    mapping (uint => OutstandingOffers) private _outstandingOffers;

    constructor(string memory uri, address settingsAddr) ERC1155(uri) Ownable() ReentrancyGuard() {
        _settingsAddr = settingsAddr;
        _mint(msg.sender, DIAMOND_TOKEN_ID, DIAMOND_TOKEN_AMOUNT, EMPTY_BYTES);
        _mint(msg.sender, GOLDEN_TOKEN_ID, GOLDEN_TOKEN_AMOUNT, EMPTY_BYTES);
    }

    function switchSettings(address settingsAddr) external onlyOwner {
        require(settingsAddr != address(0), "AD");
        _settingsAddr = settingsAddr;
    }

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) external override onlyOwner {
        require (balanceOf(msg.sender, tokenId) >= amount, "AM");
        safeTransferFrom(msg.sender, receiver, tokenId, amount, EMPTY_BYTES);
    }

    function offer(uint tokenId, uint amount, uint256 totalPrice) external override returns (uint256) {
        uint balance = balanceOf(msg.sender, tokenId);
        OutstandingOffers storage offers = _outstandingOffers[tokenId];
        uint requiredAmount = amount+offers.offerAmountBySeller[msg.sender]+_outstandingAuctions[tokenId].auctionAmountBySeller[msg.sender];
        require (balance >= requiredAmount, "BA");

        uint256 offerId = BCEMusicOffer.offer(
            msg.sender
            , offers
            , amount
            , totalPrice
        );
        emit OfferCreated(tokenId, offerId, offers.offers[offerId].terms);

        return offerId;
    }

    function acceptOffer(uint tokenId, uint256 offerId) external payable override nonReentrant {
        OfferTerms memory theOfferTermsCopy = BCEMusicOffer.acceptOffer(
            msg.value
            , _outstandingOffers[tokenId]
            , offerId
        );
        
        uint ownerPct = IBCEMusicSettings(_settingsAddr).ownerFeePercentForSecondaryMarket();
        uint256 ownerFee = theOfferTermsCopy.totalPrice*ownerPct/100;
        
        _safeTransferFrom(theOfferTermsCopy.seller, msg.sender, tokenId, theOfferTermsCopy.amount, EMPTY_BYTES);
        payable(theOfferTermsCopy.seller).transfer(theOfferTermsCopy.totalPrice-ownerFee);
        payable(owner()).transfer(ownerFee);
        if (msg.value > theOfferTermsCopy.totalPrice) {
            unchecked {
                //because of the condition, no need to check for underflow
                payable(msg.sender).transfer(msg.value-theOfferTermsCopy.totalPrice);
            }
        }
        emit OfferFilled(tokenId, offerId, theOfferTermsCopy);
    }

    function withdrawOffer(uint tokenId, uint256 offerId) external override {
        OfferTerms memory theOfferTermsCopy = BCEMusicOffer.withdrawOffer(
            msg.sender
            , _outstandingOffers[tokenId]
            , offerId
        );
        emit OfferWithdrawn(tokenId, offerId, theOfferTermsCopy);
    }

    function getOutstandingOfferById(uint tokenId, uint256 offerId) external view override returns (OfferTerms memory) {
        return BCEMusicOffer.getOutstandingOfferById(_outstandingOffers[tokenId], offerId);
    }
    function getAllOutstandingOffersOnToken(uint tokenId) external view override returns (OfferTerms[] memory) {
        return BCEMusicOffer.getAllOutstandingOffers(_outstandingOffers[tokenId]);
    }

    function startAuction(uint tokenId, uint amount, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealingPeriodSeconds, uint bidCountLimit) external override returns (uint256) {
        uint balance = balanceOf(msg.sender, tokenId);
        OutstandingAuctions storage auctions = _outstandingAuctions[tokenId];
        uint requiredAmount = amount+auctions.auctionAmountBySeller[msg.sender]+_outstandingOffers[tokenId].offerAmountBySeller[msg.sender];
        require (balance >= requiredAmount, "BA");

        uint auctionId = BCEMusicAuction.startAuction(msg.sender, auctions, amount, reservePricePerUnit, biddingPeriodSeconds, revealingPeriodSeconds, bidCountLimit);
        
        emit AuctionCreated(tokenId, auctionId, auctions.auctions[auctionId].terms);

        return auctionId;
    }
    function bidOnAuction(uint tokenId, uint256 auctionId, uint amount, bytes32 bidHash) external payable override returns (uint256) {
        uint bidId = BCEMusicAuction.bidOnAuction(
            msg.sender
            , msg.value
            , _outstandingAuctions[tokenId].auctions[auctionId]
            , amount
            , bidHash
            );
        
        emit BidPlacedForAuction(tokenId, auctionId, bidId, _outstandingAuctions[tokenId].auctions[auctionId].bids[bidId]);
        return bidId;
    }
    function revealBidOnAuction(uint tokenId, uint256 auctionId, uint bidId, uint256 totalPrice, bytes32 nonce) external payable nonReentrant override {
        Auction storage auction = _outstandingAuctions[tokenId].auctions[auctionId];
        uint refund = BCEMusicAuction.revealBidOnAuction(
            msg.sender
            , msg.value
            , auction
            , bidId
            , totalPrice
            , nonce
        );
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }
        emit BidRevealedForAuction(tokenId, auctionId, bidId, auction.bids[bidId], auction.revealedBids[auction.revealedBids.length-1]);
    }
    function finalizeAuction(uint tokenId, uint256 auctionId) external override nonReentrant {
        BCEMusicAuction.AuctionResult memory auctionResult = BCEMusicAuction.finalizeAuction(_outstandingAuctions[tokenId], auctionId);
        uint ownerPct = IBCEMusicSettings(_settingsAddr).ownerFeePercentForAuction();
        
        if (auctionResult.winners.length == 0) {
            uint256 ownerFee = auctionResult.totalReceipt*ownerPct/100;
            payable(owner()).transfer(ownerFee);
            payable(auctionResult.terms.seller).transfer(auctionResult.totalReceipt-ownerFee);
        } else {
            for (uint ii=0; ii<auctionResult.sends.length; ++ii) {
                if (auctionResult.sends[ii].receiver == address(0)) {
                    break;
                }
                if (auctionResult.sends[ii].amount > 0) {
                    _safeTransferFrom(auctionResult.terms.seller, auctionResult.sends[ii].receiver, tokenId, auctionResult.sends[ii].amount, EMPTY_BYTES);
                }
            }

            uint256 totalReceipt = auctionResult.totalReceipt;
        
            for (uint ii=0; ii<auctionResult.sends.length; ++ii) {
                if (auctionResult.sends[ii].receiver == address(0)) {
                    break;
                }
                if (auctionResult.sends[ii].value > 0) {
                    totalReceipt -= auctionResult.sends[ii].value;
                    payable(auctionResult.sends[ii].receiver).transfer(auctionResult.sends[ii].value);
                }
            }
            uint256 ownerFee = totalReceipt*ownerPct/100;
            payable(owner()).transfer(ownerFee);
            payable(auctionResult.terms.seller).transfer(totalReceipt-ownerFee);

            emit AuctionFinalized(tokenId, auctionId, auctionResult.terms, auctionResult.winners);
        }
    }

    function getAuctionById(uint tokenId, uint256 auctionId) external view override returns (AuctionTerms memory) {
        return BCEMusicAuction.getAuctionById(_outstandingAuctions[tokenId], auctionId);
    }
    function getAllAuctionsOnToken(uint tokenId) external view override returns (AuctionTerms[] memory) {
        return BCEMusicAuction.getAllAuctions(_outstandingAuctions[tokenId]);
    }
}
