// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IBCEMusic.sol";
import "./IBCEMusicSettings.sol";

contract BCEMusic is ERC1155, Ownable, ReentrancyGuard, IBCEMusic {

    uint public constant DIAMOND_TOKEN_AMOUNT = 1;
    uint public constant GOLDEN_TOKEN_AMOUNT = 499;
    uint public constant AMOUNT_UPPER_LIMIT = 500;

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
        require(settingsAddr != address(0), "bad address.");
        _settingsAddr = settingsAddr;
    }

    function airDropInitialOwner(address receiver, uint tokenId, uint amount) external override onlyOwner {
        if (balanceOf(msg.sender, tokenId) < amount){
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: amount
                });
        }
        safeTransferFrom(msg.sender, receiver, tokenId, amount, "");
    }

    function offer(uint tokenId, uint amount, uint256 totalPrice) external override returns (uint256) {
        require((tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID), "Invalid token id.");
        require(amount > 0, "Invalid amount.");
        require(amount < AMOUNT_UPPER_LIMIT, "Invalid amount.");
        require(totalPrice > 0, "Invalid price.");

        uint balance = balanceOf(msg.sender, tokenId);
        OutstandingOffers storage offers = _outstandingOffers[tokenId];
        uint requiredAmount = amount+offers.offerAmountBySeller[msg.sender]+_outstandingAuctions[tokenId].auctionAmountBySeller[msg.sender];
        if (balance < requiredAmount) {
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: requiredAmount
                });
        }
        
        Counters.increment(offers.offerIdCounter);
        uint256 offerId = Counters.current(offers.offerIdCounter);
        offers.offers[offerId] = Offer({
            terms: OfferTerms({
                seller: msg.sender 
                , amount: amount
                , totalPrice: totalPrice
            })
            , nextOffer: 0
            , prevOffer: offers.lastOfferId
        });
        if (offers.firstOfferId != 0) {
            offers.offers[offers.lastOfferId].nextOffer = offerId;
        } else {
            offers.firstOfferId = offerId;
        }
        offers.lastOfferId = offerId;
        unchecked {
            ++offers.totalCount;
            offers.totalOfferAmount += amount;
            offers.offerAmountBySeller[msg.sender] += amount;
        }
        emit OfferCreated(tokenId, offerId, offers.offers[offerId].terms);

        return offerId;
    }

    function _removeOffer(OutstandingOffers storage outstandingOffers, uint256 offerId, Offer storage theOffer) private returns (OfferTerms memory) {
        if (theOffer.prevOffer == 0) {
            outstandingOffers.firstOfferId = theOffer.nextOffer;
            if (theOffer.nextOffer != 0) {
                outstandingOffers.offers[theOffer.nextOffer].prevOffer = 0;
            } else {
                outstandingOffers.lastOfferId = 0;
            }
        } else {
            outstandingOffers.offers[theOffer.prevOffer].nextOffer = theOffer.nextOffer;
            if (theOffer.nextOffer != 0) {
                outstandingOffers.offers[theOffer.nextOffer].prevOffer = theOffer.prevOffer;
            } else {
                outstandingOffers.lastOfferId = theOffer.prevOffer;
            }
        }
        OfferTerms memory theOfferTermsCopy = theOffer.terms;
        theOffer.terms.amount = 0;
        
        unchecked {
            --outstandingOffers.totalCount;
            outstandingOffers.totalOfferAmount -= theOfferTermsCopy.amount;
            outstandingOffers.offerAmountBySeller[theOfferTermsCopy.seller] -= theOfferTermsCopy.amount;
        }

        delete(outstandingOffers.offers[offerId]);

        return theOfferTermsCopy;
    }

    function acceptOffer(uint tokenId, uint256 offerId) external payable override nonReentrant {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (offerId > 0, "Invalid order id.");

        OutstandingOffers storage outstandingOffers = _outstandingOffers[tokenId];
        Offer storage theOffer = outstandingOffers.offers[offerId];   
        require (theOffer.terms.amount > 0, "Invalid offer.");     

        if (msg.value < theOffer.terms.totalPrice){
            revert InsufficientBalance({
                paid: msg.value,
                price: theOffer.terms.totalPrice
            });
        }

        OfferTerms memory theOfferTermsCopy = _removeOffer(outstandingOffers, offerId, theOffer);
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
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (offerId > 0, "Invalid order id.");

        OutstandingOffers storage outstandingOffers = _outstandingOffers[tokenId];
        Offer storage theOffer = outstandingOffers.offers[offerId]; 
        require (theOffer.terms.amount > 0, "Invalid offer.");
        require (msg.sender == theOffer.terms.seller, "Wrong seller");

        OfferTerms memory theOfferTermsCopy = _removeOffer(outstandingOffers, offerId, theOffer);

        emit OfferWithdrawn(tokenId, offerId, theOfferTermsCopy);
    }

    function getOutstandingOfferById(uint tokenId, uint256 offerId) external view override returns (OfferTerms memory) {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (offerId > 0, "Invalid offer id.");
        OfferTerms memory theOfferTermsCopy = _outstandingOffers[tokenId].offers[offerId].terms;
        return theOfferTermsCopy;
    }
    function getAllOutstandingOffersOnToken(uint tokenId) external view override returns (OfferTerms[] memory) {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");

        OutstandingOffers storage outstandingOffers = _outstandingOffers[tokenId];
        if (outstandingOffers.totalCount == 0) {
            return new OfferTerms[](0);
        }
        OfferTerms[] memory theOfferTerms = new OfferTerms[](outstandingOffers.totalCount);
        uint256 id = outstandingOffers.firstOfferId;
        uint outputIdx = 0;
        while (id != 0 && outputIdx < theOfferTerms.length) {
            Offer storage o = outstandingOffers.offers[id];
            theOfferTerms[outputIdx] = o.terms;
            unchecked {
                ++outputIdx;
            }
            id = o.nextOffer;
        }
        return theOfferTerms;
    }

    function startAuction(uint tokenId, uint amount, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealPeriodSeconds) external override returns (uint256) {
        require((tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID), "Invalid token id.");
        require(amount > 0, "Invalid amount.");
        require(amount < AMOUNT_UPPER_LIMIT, "Invalid amount.");
        require(reservePricePerUnit > 0, "Invalid reserve price.");

        uint balance = balanceOf(msg.sender, tokenId);
        OutstandingAuctions storage auctions = _outstandingAuctions[tokenId];
        uint requiredAmount = amount+auctions.auctionAmountBySeller[msg.sender]+_outstandingOffers[tokenId].offerAmountBySeller[msg.sender];
        if (balance < requiredAmount) {
            revert InsufficientNFT({
                    ownedAmount: balanceOf(msg.sender, tokenId), 
                    requiredAmount: requiredAmount
                });
        }
        
        Counters.increment(auctions.auctionIdCounter);
        uint256 auctionId = Counters.current(auctions.auctionIdCounter);
        Auction storage auction = auctions.auctions[auctionId];
        auction.terms = AuctionTerms({
            seller: msg.sender 
            , amount: amount
            , reservePricePerUnit: reservePricePerUnit
            , biddingDeadline: block.timestamp+biddingPeriodSeconds
            , revealingDeadline: block.timestamp+biddingPeriodSeconds+revealPeriodSeconds
        });
        auction.prevAuction = auctions.lastAuctionId;
        if (auctions.firstAuctionId != 0) {
            auctions.auctions[auctions.lastAuctionId].nextAuction = auctionId;
        } else {
            auctions.firstAuctionId = auctionId;
        }
        auctions.lastAuctionId = auctionId;
        unchecked {
            ++auctions.totalCount;
            auctions.totalAuctionAmount += amount;
            auctions.auctionAmountBySeller[msg.sender] += amount;
        }
        emit AuctionCreated(tokenId, auctionId, auctions.auctions[auctionId].terms);

        return auctionId;
    }
    //since bid does not send money anywhere, we don't mark it as nonReentrant
    function bidOnAuction(uint tokenId, uint256 auctionId, uint amount, bytes32 bidHash) external payable override returns (uint256) {
        require((tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID), "Invalid token id.");
        require(amount > 0, "Invalid amount.");

        Auction storage auction = _outstandingAuctions[tokenId].auctions[auctionId];
        require(auction.terms.amount > 0, "Invalid auction.");
        require(amount <= auction.terms.amount, "Excessive amount.");
        require(msg.value >= auction.terms.reservePricePerUnit*amount*2, "Insufficient earnest money");
        require(block.timestamp <= auction.terms.biddingDeadline, "Bidding has closed.");
        uint bidLimit = IBCEMusicSettings(_settingsAddr).auctionBidLimit();
        require(auction.bids.length < bidLimit, "Too many bids.");

        auction.bids.push(Bid({
            bidder: msg.sender
            , amount: amount
            , earnestMoney: msg.value
            , bidHash: bidHash
            , revealed: false
        }));
        uint bidId = auction.bids.length-1;
        auction.totalHeldBalance += msg.value;
        
        emit BidPlacedForAuction(tokenId, auctionId, bidId, auction.bids[bidId]);
        return bidId;
    }
    function revealBidOnAuctionAndPayDifference(uint tokenId, uint256 auctionId, uint bidId, bytes32 nonce) external payable override {
        require((tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID), "Invalid token id.");

        Auction storage auction = _outstandingAuctions[tokenId].auctions[auctionId];
        require(auction.terms.amount > 0, "Invalid auction.");
        require(bidId <= auction.bids.length, "Invalid bid id.");
        require(block.timestamp <= auction.terms.revealingDeadline, "Revealing has closed.");
        
        Bid storage bid = auction.bids[bidId];
        require(msg.sender == bid.bidder, "Not your bid.");
        require(!bid.revealed, "Duplicate revealing");

        uint256 totalPrice = msg.value+bid.earnestMoney;
        bytes memory toHash = abi.encodePacked(totalPrice, nonce);
        bytes32 theHash = keccak256(toHash);
        require(theHash == bid.bidHash, "Hash does not match.");

        auction.revealedBids.push(RevealedBid({
            id: bidId 
            , totalPrice: totalPrice
        }));
        bid.revealed = true;
        auction.totalHeldBalance += msg.value;
        
        emit BidRevealedForAuction(tokenId, auctionId, bidId, auction.bids[bidId], auction.revealedBids[auction.revealedBids.length-1]);
    }
    function revealBidOnAuctionAndGetRefund(uint tokenId, uint256 auctionId, uint bidId, uint256 totalPrice, bytes32 nonce) external nonReentrant override {
        require((tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID), "Invalid token id.");

        Auction storage auction = _outstandingAuctions[tokenId].auctions[auctionId];
        require(auction.terms.amount > 0, "Invalid auction.");
        require(bidId <= auction.bids.length, "Invalid bid id.");
        require(block.timestamp <= auction.terms.revealingDeadline, "Revealing has closed.");
        
        Bid storage bid = auction.bids[bidId];
        require(msg.sender == bid.bidder, "Not your bid.");
        require(!bid.revealed, "Duplicate revealing");
        require(totalPrice <= bid.earnestMoney, "Pay difference instead.");
        require(totalPrice >= auction.terms.reservePricePerUnit*bid.amount, "Not meeting reserve.");

        bytes memory toHash = abi.encodePacked(totalPrice, nonce);
        bytes32 theHash = keccak256(toHash);
        require(theHash == bid.bidHash, "Hash does not match.");

        uint256 refund;
        unchecked {
            refund = bid.earnestMoney-totalPrice;
        }

        auction.revealedBids.push(RevealedBid({
            id: bidId 
            , totalPrice: totalPrice
        }));
        bid.revealed = true;

        if (refund > 0) {
            auction.totalHeldBalance -= refund;
            payable(msg.sender).transfer(refund);
        }
        
        emit BidRevealedForAuction(tokenId, auctionId, bidId, auction.bids[bidId], auction.revealedBids[auction.revealedBids.length-1]);
    }

    struct OneSend {
        address receiver;
        uint amount;
        uint256 value;
    }
    function _buildFinalBids(Auction storage auction) private view returns (uint256[] memory) {
        uint256[] memory finalBids = new uint256[](auction.revealedBids.length);
        for (uint ii=0; ii<finalBids.length; ++ii) {
            RevealedBid storage b = auction.revealedBids[ii];
            finalBids[ii] = (b.totalPrice/auction.bids[b.id].amount)*1000+(200-ii);
            uint jj = ii;
            while (jj > 0) {
                uint upper = (jj-1)/2;
                if (finalBids[jj] > finalBids[upper]) {
                    uint t = finalBids[upper];
                    finalBids[upper] = finalBids[jj];
                    finalBids[jj] = t;
                }
                jj = upper;
            }
        }
        return finalBids;
    }
    function _buildPotentialWinners(Auction storage auction, uint256[] memory finalBids) private view returns (AuctionWinner[] memory) {
        AuctionWinner[] memory potentialWinners = new AuctionWinner[](auction.revealedBids.length);
        uint totalAmount = 0;
        uint auctionAmount = auction.terms.amount;
        bool breakNextTime = false;
        for (uint ii=0; ii<potentialWinners.length; ++ii) {
            RevealedBid storage r = auction.revealedBids[finalBids[200-((uint) (finalBids[0]%1000))]];
            potentialWinners[ii] = AuctionWinner({
                bidder : auction.bids[r.id].bidder 
                , amount: auction.bids[r.id].amount
                , pricePerUnit: finalBids[0]/1000
                , actuallyPaid : r.totalPrice
            });
            if (breakNextTime) {
                break;
            }
            totalAmount += auction.bids[r.id].amount;
            if (totalAmount >= auctionAmount) {
                breakNextTime = true;
            }
            finalBids[0] = finalBids[potentialWinners.length-1-ii];
            uint jj=0;
            while (true) {
                uint left = jj*2+1;
                uint right = left+1;
                if (right < potentialWinners.length-1-ii) {
                    if (finalBids[left] > finalBids[right]) {
                        if (finalBids[jj] < finalBids[left]) {
                            uint t = finalBids[jj];
                            finalBids[jj] = finalBids[left];
                            finalBids[left] = t;
                            jj = left;
                        } else {
                            break;
                        }
                    } else {
                        if (finalBids[jj] < finalBids[right]) {
                            uint t = finalBids[jj];
                            finalBids[jj] = finalBids[right];
                            finalBids[right] = t;
                            jj = right;
                        } else {
                            break;
                        }
                    }
                } else if (left < potentialWinners.length-1-ii) {
                    if (finalBids[jj] < finalBids[left]) {
                        uint t = finalBids[jj];
                        finalBids[jj] = finalBids[left];
                        finalBids[left] = t;
                        jj = left;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
        }
        return potentialWinners;
    }
    function _removeAuction(uint tokenId, uint256 auctionId, Auction storage auction) private returns (AuctionTerms memory) {
        OutstandingAuctions storage auctions = _outstandingAuctions[tokenId];
        if (auction.prevAuction == 0) {
            auctions.firstAuctionId = auction.nextAuction;
            if (auction.nextAuction != 0) {
                auctions.auctions[auction.nextAuction].prevAuction = 0;
            } else {
                auctions.lastAuctionId = 0;
            }
        } else {
            auctions.auctions[auction.prevAuction].nextAuction = auction.nextAuction;
            if (auction.nextAuction != 0) {
                auctions.auctions[auction.nextAuction].prevAuction = auction.prevAuction;
            } else {
                auctions.lastAuctionId = auction.prevAuction;
            }
        }
        
        unchecked {
            --auctions.totalCount;
            auctions.totalAuctionAmount -= auction.terms.amount;
            auctions.auctionAmountBySeller[auction.terms.seller] -= auction.terms.amount;
        }

        AuctionTerms memory terms = auction.terms;
        delete(auctions.auctions[auctionId]);

        return terms;
    }
    function finalizeAuction(uint tokenId, uint256 auctionId) external override nonReentrant {
        require((tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID), "Invalid token id.");

        Auction storage auction = _outstandingAuctions[tokenId].auctions[auctionId];
        require(auction.terms.amount > 0, "Invalid auction.");
        require(block.timestamp > auction.terms.revealingDeadline, "Immature finalizing");

        uint ownerPct = IBCEMusicSettings(_settingsAddr).ownerFeePercentForAuction();
        if (auction.revealedBids.length == 0) {
            uint256 ownerFee = auction.totalHeldBalance*ownerPct/100;
            payable(owner()).transfer(ownerFee);
            payable(auction.terms.seller).transfer(auction.totalHeldBalance-ownerFee);
        } else {
            uint256[] memory finalBids = _buildFinalBids(auction);
            AuctionWinner[] memory potentialWinners = _buildPotentialWinners(auction, finalBids);
            uint winnerCount = 0;
            OneSend[] memory sends = new OneSend[](potentialWinners.length);
            uint cumAmount = 0;
            for (uint ii=0; ii<potentialWinners.length; ++ii) {
                if (ii+1 < potentialWinners.length) {
                    potentialWinners[ii].pricePerUnit = potentialWinners[ii+1].pricePerUnit;
                } else {
                    potentialWinners[ii].pricePerUnit = auction.terms.reservePricePerUnit;
                }
                if (cumAmount + potentialWinners[ii].amount >= auction.terms.amount) {
                    potentialWinners[ii].amount = auction.terms.amount-cumAmount;
                }
                for (uint jj=0; jj<winnerCount; ++ii) {
                    if (sends[jj].receiver == potentialWinners[ii].bidder) {
                        sends[jj].amount += potentialWinners[ii].amount;
                        sends[jj].value += potentialWinners[ii].actuallyPaid-potentialWinners[ii].pricePerUnit*potentialWinners[ii].amount;
                        break;
                    } else if (sends[jj].receiver == address(0)) {
                        sends[jj].receiver = potentialWinners[ii].bidder;
                        sends[jj].amount += potentialWinners[ii].amount;
                        sends[jj].value += potentialWinners[ii].actuallyPaid-potentialWinners[ii].pricePerUnit*potentialWinners[ii].amount;
                        break;
                    }
                }
                cumAmount += potentialWinners[ii].amount;
            }

            for (uint ii=0; ii<sends.length; ++ii) {
                if (sends[ii].receiver == address(0)) {
                    break;
                }
                if (sends[ii].amount > 0) {
                    _safeTransferFrom(auction.terms.seller, sends[ii].receiver, tokenId, sends[ii].amount, EMPTY_BYTES);
                }
            }

            uint256 totalReceipt = auction.totalHeldBalance;
            AuctionTerms memory terms = _removeAuction(tokenId, auctionId, auction);
        
            for (uint ii=0; ii<sends.length; ++ii) {
                if (sends[ii].receiver == address(0)) {
                    break;
                }
                if (sends[ii].value > 0) {
                    totalReceipt -= sends[ii].value;
                    payable(sends[ii].receiver).transfer(sends[ii].value);
                }
            }
            uint256 ownerFee = totalReceipt*ownerPct/100;
            payable(owner()).transfer(ownerFee);
            payable(terms.seller).transfer(totalReceipt-ownerFee);

            emit AuctionFinalized(tokenId, auctionId, terms, potentialWinners);
        }
    }

    function getAuctionById(uint tokenId, uint256 auctionId) external view override returns (AuctionTerms memory) {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");
        require (auctionId > 0, "Invalid auction id.");
        AuctionTerms memory theTermsCopy = _outstandingAuctions[tokenId].auctions[auctionId].terms;
        return theTermsCopy;
    }
    function getAllAuctionsOnToken(uint tokenId) external view override returns (AuctionTerms[] memory) {
        require (tokenId == DIAMOND_TOKEN_ID || tokenId == GOLDEN_TOKEN_ID, "Invalid token id.");

        OutstandingAuctions storage outstandingAuctions = _outstandingAuctions[tokenId];
        if (outstandingAuctions.totalCount == 0) {
            return new AuctionTerms[](0);
        }
        AuctionTerms[] memory theTerms = new AuctionTerms[](outstandingAuctions.totalCount);
        uint256 id = outstandingAuctions.firstAuctionId;
        uint outputIdx = 0;
        while (id != 0 && outputIdx < theTerms.length) {
            Auction storage o = outstandingAuctions.auctions[id];
            theTerms[outputIdx] = o.terms;
            unchecked {
                ++outputIdx;
            }
            id = o.nextAuction;
        }
        return theTerms;
    }
}
