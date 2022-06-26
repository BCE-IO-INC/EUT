// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./IBCEMusic.sol";
import "./IBCEMusicSettings.sol";
import "./BCEMusicAuction.sol";
import "./BCEMusicOffer.sol";

//import "hardhat/console.sol";

contract BCEMusic is ERC1155, Ownable, ReentrancyGuard, IBCEMusic {

    uint public constant DIAMOND_TOKEN_AMOUNT = 1;
    uint public constant GOLDEN_TOKEN_AMOUNT = 499;

    uint public constant DIAMOND_TOKEN_ID = 1;
    uint public constant GOLDEN_TOKEN_ID = 2;

    bytes private constant EMPTY_BYTES = "";

    address private _settingsAddr;

    mapping (uint256 => OutstandingAuctions) private _outstandingAuctions;
    mapping (uint256 => OutstandingOffers) private _outstandingOffers;
    mapping (address => uint256) private _withdrawalAllowances;

    constructor(string memory uri, address settingsAddr) ERC1155(uri) Ownable() ReentrancyGuard() {
        _settingsAddr = settingsAddr;
        _mint(msg.sender, DIAMOND_TOKEN_ID, DIAMOND_TOKEN_AMOUNT, EMPTY_BYTES);
        _mint(msg.sender, GOLDEN_TOKEN_ID, GOLDEN_TOKEN_AMOUNT, EMPTY_BYTES);
    }

    function switchSettings(address settingsAddr) external onlyOwner {
        require(settingsAddr != address(0), "AD");
        _settingsAddr = settingsAddr;
    }

    function airDropInitialOwner(address receiver, uint256 tokenId, uint16 amount) external override onlyOwner {
        require (balanceOf(msg.sender, tokenId) >= amount, "AM");
        safeTransferFrom(msg.sender, receiver, tokenId, amount, EMPTY_BYTES);
    }

    function offer(uint256 tokenId, uint16 amount, uint256 totalPrice) external override returns (uint64) {
        uint balance = balanceOf(msg.sender, tokenId);
        OutstandingOffers storage offers = _outstandingOffers[tokenId];
        uint requiredAmount = amount+offers.offerAmountBySeller[msg.sender]+_outstandingAuctions[tokenId].auctionAmountBySeller[msg.sender];
        require (balance >= requiredAmount, "BA");

        uint64 offerId = BCEMusicOffer.offer(
            msg.sender
            , offers
            , amount
            , totalPrice
        );
        emit OfferCreated(tokenId, offerId);

        //console.log("Offer id is %s", offerId);
        return offerId;
    }

    function acceptOffer(uint256 tokenId, uint64 offerId) external payable override {
        OfferTerms memory theOfferTermsCopy = BCEMusicOffer.acceptOffer(
            msg.value
            , _outstandingOffers[tokenId]
            , offerId
        );
        
        //owner fee percentage is always resolved from contract call
        //thus allowing easier adjustments
        uint ownerPct = IBCEMusicSettings(_settingsAddr).ownerFeePercentForSecondaryMarket();
        uint256 ownerFee = theOfferTermsCopy.totalPrice*ownerPct/100;
        
        //The token transfer happens immediately, but the payment is not
        //transferred automatically, they must be claimed later. 
        //As payments are not transferred, there is no need to mark the whole
        //function as non reentrant.
        _safeTransferFrom(theOfferTermsCopy.seller, msg.sender, tokenId, theOfferTermsCopy.amount, EMPTY_BYTES);
        if (owner() != theOfferTermsCopy.seller) {
            _withdrawalAllowances[theOfferTermsCopy.seller] += theOfferTermsCopy.totalPrice-ownerFee;
            _withdrawalAllowances[owner()] += ownerFee;
            emit ClaimIncreased(theOfferTermsCopy.seller, theOfferTermsCopy.totalPrice-ownerFee);
            emit ClaimIncreased(owner(), ownerFee);
        } else {
            _withdrawalAllowances[owner()] += theOfferTermsCopy.totalPrice;
            emit ClaimIncreased(owner(), theOfferTermsCopy.totalPrice);
        }
        if (msg.value > theOfferTermsCopy.totalPrice) {
            _withdrawalAllowances[msg.sender] += msg.value-theOfferTermsCopy.totalPrice;
            emit ClaimIncreased(msg.sender, msg.value-theOfferTermsCopy.totalPrice);
        }
        emit OfferFilled(tokenId, offerId);
    }

    function withdrawOffer(uint256 tokenId, uint64 offerId) external override {
        BCEMusicOffer.withdrawOffer(
            msg.sender
            , _outstandingOffers[tokenId]
            , offerId
        );
        emit OfferWithdrawn(tokenId, offerId);
    }

    function getOutstandingOfferById(uint256 tokenId, uint64 offerId) external view override returns (OfferTerms memory) {
        return BCEMusicOffer.getOutstandingOfferById(_outstandingOffers[tokenId], offerId);
    }
    function getAllOutstandingOffersOnToken(uint256 tokenId) external view override returns (OfferTerms[] memory) {
        return BCEMusicOffer.getAllOutstandingOffers(_outstandingOffers[tokenId]);
    }

    function startAuction(uint256 tokenId, uint16 amount, uint16 minimumBidAmount, uint16 bidUnit, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealingPeriodSeconds) external override returns (uint64) {
        uint balance = balanceOf(msg.sender, tokenId);
        OutstandingAuctions storage auctions = _outstandingAuctions[tokenId];
        uint requiredAmount = amount+auctions.auctionAmountBySeller[msg.sender]+_outstandingOffers[tokenId].offerAmountBySeller[msg.sender];
        require (balance >= requiredAmount, "BA");

        uint64 auctionId = BCEMusicAuction.startAuction(msg.sender, auctions, amount, minimumBidAmount, bidUnit, reservePricePerUnit, biddingPeriodSeconds, revealingPeriodSeconds);
        
        emit AuctionCreated(tokenId, auctionId);

        return auctionId;
    }
    function bidOnAuction(uint256 tokenId, uint64 auctionId, uint16 amount, bytes32 bidHash) external override returns (uint32) {
        uint32 bidId = BCEMusicAuction.bidOnAuction(
            msg.sender
            , _outstandingAuctions[tokenId].auctions[auctionId]
            , amount
            , bidHash
            );
        
        emit BidPlacedForAuction(tokenId, auctionId, bidId);
        return bidId;
    }
    function revealBidOnAuction(uint256 tokenId, uint64 auctionId, uint32 bidId, uint256 pricePerUnit, bytes12 nonce) external payable override {
        Auction storage auction = _outstandingAuctions[tokenId].auctions[auctionId];
        BCEMusicAuction.revealBidOnAuction(
            msg.sender
            , msg.value
            , auction
            , bidId
            , pricePerUnit
            , nonce
            , _withdrawalAllowances
        );
        emit BidRevealedForAuction(tokenId, auctionId, bidId);
    }
    function finalizeAuction(uint256 tokenId, uint64 auctionId) external override {
        BCEMusicAuction.AuctionResult memory auctionResult = BCEMusicAuction.finalizeAuction(_outstandingAuctions[tokenId], auctionId);
        uint ownerPct = IBCEMusicSettings(_settingsAddr).ownerFeePercentForAuction();
        
        if (auctionResult.winners.length == 0) {
            if (owner() != auctionResult.terms.seller) {
                uint256 ownerFee = auctionResult.totalReceipt*ownerPct/100;
                _withdrawalAllowances[owner()] += ownerFee;
                _withdrawalAllowances[auctionResult.terms.seller] += auctionResult.totalReceipt-ownerFee;
                emit ClaimIncreased(owner(), ownerFee);
                emit ClaimIncreased(auctionResult.terms.seller, auctionResult.totalReceipt-ownerFee);
            } else {
                _withdrawalAllowances[owner()] += auctionResult.totalReceipt;
                emit ClaimIncreased(owner(), auctionResult.totalReceipt);
            }
        } else {
            uint256 totalReceipt = auctionResult.totalReceipt;
            //console.log("Got winners %s", auctionResult.winners.length);
            for (uint ii=0; ii<auctionResult.winners.length; ++ii) {
                uint amt = auctionResult.winners[ii].amount;
                //console.log("Send %s %s", auctionResult.winners[ii].bidder, amt);
                if (amt > 0) {
                    _safeTransferFrom(auctionResult.terms.seller, auctionResult.winners[ii].bidder, tokenId, amt, EMPTY_BYTES);
                }
                uint256 refund = auctionResult.winners[ii].refund;
                if (refund > 0) {
                    totalReceipt -= refund;
                    _withdrawalAllowances[auctionResult.winners[ii].bidder] += refund;
                    emit ClaimIncreased(auctionResult.winners[ii].bidder, refund);
                }
            }
            //console.log("Finalize %s", totalReceipt);
            if (owner() != auctionResult.terms.seller) {
                uint256 ownerFee = totalReceipt*ownerPct/100;
                _withdrawalAllowances[owner()] += ownerFee;
                _withdrawalAllowances[auctionResult.terms.seller] += totalReceipt-ownerFee;
                emit ClaimIncreased(owner(), ownerFee);
                emit ClaimIncreased(auctionResult.terms.seller, totalReceipt-ownerFee);
            } else {
                _withdrawalAllowances[owner()] += totalReceipt;
                emit ClaimIncreased(owner(), totalReceipt);
            }

            emit AuctionFinalized(tokenId, auctionId);
        }
    }

    function getAuctionById(uint256 tokenId, uint64 auctionId) external view override returns (AuctionTerms memory) {
        return BCEMusicAuction.getAuctionById(_outstandingAuctions[tokenId], auctionId);
    }
    function getAllAuctionsOnToken(uint256 tokenId) external view override returns (AuctionTerms[] memory) {
        return BCEMusicAuction.getAllAuctions(_outstandingAuctions[tokenId]);
    }

    function claimWithdrawal() external override nonReentrant {
        uint256 fund = _withdrawalAllowances[msg.sender];
        if (fund > 0) {
            _withdrawalAllowances[msg.sender] = 0;
            uint256 amt = Math.min(fund, address(this).balance);
            payable(msg.sender).transfer(amt);
            emit ClaimWithdrawn(msg.sender, amt);
        }
    }
}
