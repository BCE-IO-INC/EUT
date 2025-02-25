// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IBCEMusic.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
//import "hardhat/console.sol";

library BCEMusicAuction {
    uint public constant AMOUNT_UPPER_LIMIT = 500;

    //This function simply adds an auction to the double-linked list and returns its ID
    function startAuction(address seller, IBCEMusic.OutstandingAuctions storage auctions, uint16 amount, uint16 minimumBidAmount, uint16 bidUnit, uint256 reservePricePerUnit, uint256 biddingPeriodSeconds, uint256 revealingPeriodSeconds) external returns (uint64) {
        require(amount > 0 && amount < AMOUNT_UPPER_LIMIT, "Invalid amount.");
        require(minimumBidAmount <= amount, "Invalid minimum bid amount.");
        require(bidUnit <= amount, "Invalid bid unit.");
        require(reservePricePerUnit > 0, "Invalid reserve price.");
      
        ++auctions.auctionIdCounter;
        uint64 auctionId = auctions.auctionIdCounter;
        IBCEMusic.Auction storage auction = auctions.auctions[auctionId];
        auction.terms = IBCEMusic.AuctionTerms({
            amount: amount
            , minimumBidAmount : minimumBidAmount 
            , bidUnit : bidUnit
            , seller: seller 
            , reservePricePerUnit: reservePricePerUnit
            , biddingDeadline: block.timestamp+biddingPeriodSeconds
            , revealingDeadline: block.timestamp+biddingPeriodSeconds+revealingPeriodSeconds
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
            auctions.auctionAmountBySeller[seller] += amount;
        }

        return auctionId;
    }
    //This function adds bid to the array in the auction and returns its it
    function bidOnAuction(address seller, uint256 value, IBCEMusic.Auction storage auction, uint16 amount, bytes32 bidHash) external returns (uint32) {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(amount > 0 && amount >= auction.terms.minimumBidAmount && amount <= auction.terms.amount, "Invalid amount.");
        require(auction.terms.bidUnit <= 1 || (amount%auction.terms.bidUnit) == 0, "Invalid amount unit.");
        require(value >= auction.terms.reservePricePerUnit*amount*2, "Insufficient earnest money");
        require(block.timestamp <= auction.terms.biddingDeadline, "Bidding has closed.");

        auction.bids.push(IBCEMusic.Bid({
            amountAndRevealed: amount
            , bidder: seller
            , earnestMoney: value
            , bidHash: bidHash
        }));
        uint32 bidId = (uint32) (auction.bids.length-1);
        auction.totalHeldBalance += value;
        
        return bidId;
    }
    //An revealed bid is smaller if either (1) its per-unit price is lower or
    //(2) its per-unit price is the same as the other one, but its bid id is
    //higher (i.e. it is later)
    function _compareBids(IBCEMusic.RevealedBid storage a, IBCEMusic.RevealedBid storage b) private view returns (int8) {
        if (a.pricePerUnit < b.pricePerUnit) {
            return -1;
        }
        if (a.pricePerUnit > b.pricePerUnit) {
            return 1;
        }
        if (a.bidId > b.bidId) {
            return -1;
        }
        if (a.bidId < b.bidId) {
            return 1;
        }
        return 0;
    }
    function _rotateUp(IBCEMusic.Auction storage auction, uint32 hinge) private {
        IBCEMusic.RevealedBid storage hb = auction.revealedBids[hinge];
        uint32 p = hb.parent;
        while (p != 0) {
            IBCEMusic.RevealedBid storage pb = auction.revealedBids[p];
            if (pb.blockHash < hb.blockHash) {
                if (pb.left == hinge) {
                    pb.left = hb.right;
                    hb.right = p;
                } else {
                    pb.right = hb.left;
                    hb.left = p;
                }
                uint32 nextParent = pb.parent;
                pb.parent = hinge;
                hb.parent = nextParent;
                if (nextParent == 0) {
                    auction.revealedBidRoot = hinge;
                    break;
                } else {
                    IBCEMusic.RevealedBid storage nextPB = auction.revealedBids[nextParent];
                    if (nextPB.left == p) {
                        nextPB.left = hinge;
                    } else {
                        nextPB.right = hinge;
                    }
                    p = nextParent;
                }
            } else {
                break;
            }
        }
    }
    //at the call point, we assume that the new node has been created already
    function _insertRevealedBid(IBCEMusic.Auction storage auction, uint32 newId) private {
        if (auction.revealedBidRoot == 0) {
            auction.revealedBidRoot = newId;
            return;
        }
        uint32 current = auction.revealedBidRoot;
        while (current != 0) {
            int8 c = _compareBids(auction.revealedBids[newId], auction.revealedBids[current]);
            if (c < 0) {
                if (auction.revealedBids[current].left == 0) {
                    auction.revealedBids[current].left = newId;
                    auction.revealedBids[newId].parent = current;
                    _rotateUp(auction, newId);
                    return;
                } else {
                    current = auction.revealedBids[current].left;
                }
            } else {
                if (auction.revealedBids[current].right == 0) {
                    auction.revealedBids[current].right = newId;
                    auction.revealedBids[newId].parent = current;
                    _rotateUp(auction, newId);
                    return;
                } else {
                    current = auction.revealedBids[current].right;
                }
            }
        }
    }
    //This function adds revealed bid to the single-linked list and updates statistics
    //The returned value also includes cumulative amount of all revealed bids that are
    //higher than the newly added one
    function _addRevealedBid(IBCEMusic.Auction storage auction, uint32 bidId, uint256 pricePerUnit) private {
        ++auction.revealedBidIdCounter;
        uint32 revealedBidId = auction.revealedBidIdCounter;
        auction.revealedBids[revealedBidId] = IBCEMusic.RevealedBid({
            bidId : bidId
            , left : 0
            , right : 0
            , parent : 0
            , blockHash : uint128(uint256(blockhash(block.number-1)))
            , pricePerUnit : pricePerUnit 
        });
        auction.revealedAmount += (auction.bids[bidId].amountAndRevealed & 0x7f);
        auction.totalInPlayRevealedBidCount += 1;

        _insertRevealedBid(auction, revealedBidId);
    }

    event ClaimIncreased(address claimant, uint256 increaseAmount);

    event BidWonNotification(uint256 tokenId, uint64 auctionId, uint32 bidId, uint16 amount, uint256 pricePerUnit, address bidder);
    event BidLostNotification(uint256 tokenId, uint64 auctionId, uint32 bidId, address bidder);

    //This function starts from the newly added revealed bid and eliminates
    //all out-bidded revealed bids (except at most one, to provide a reference
    //price for the next higher one)
    function _findMin(IBCEMusic.Auction storage auction) private view returns (uint32) {
        uint32 currentParent = 0;
        uint32 current = auction.revealedBidRoot;
        while (current != 0) {
            uint32 l = auction.revealedBids[current].left;
            if (l == 0) {
                return currentParent;
            } else {
                currentParent = current;
                current = l;
            }
        }
        return 0;
    }
    function _eliminateOutBiddedRevealedBids(uint256 tokenId, uint64 auctionId, IBCEMusic.Auction storage auction, mapping (address => uint256) storage withdrawalAllowances) private {
        if (auction.revealedAmount <= auction.terms.amount) {
            return;
        }
        //In this version, we at most eliminate one outbidded bid.
        //The reason is that, for each outbidded one, we need to somehow do a traversal
        //to find it. In the rare case where a huge new bid elimiates a big number of
        //outbidded ones, the gas consumption would be high, and this may discourage the
        //bidder of the huge bid from revealing it.
        //Now if we eliminate at most one, then the gas consumption for revelation would be
        //controllable, and also the final bid count will still not exceed the possible
        //high limit (equal to tokens in auction plus one), so the finalizing step would
        //still be handlable in gas.
        uint32 idxParent = _findMin(auction);
        uint32 idx = 0;
        if (idxParent == 0) {
            idx = auction.revealedBidRoot;
        } else {
            idx = auction.revealedBids[idxParent].left;
        }
        uint32 bidId = auction.revealedBids[idx].bidId;
        uint16 sz = (auction.bids[bidId].amountAndRevealed & 0x7f);
        if (auction.revealedAmount <= sz+auction.terms.amount) {
            return;
        }
        auction.revealedAmount -= sz;
        auction.totalInPlayRevealedBidCount -= 1;
        uint256 totalPrice = auction.revealedBids[idx].pricePerUnit*sz;
        auction.totalHeldBalance -= totalPrice;
        withdrawalAllowances[auction.bids[bidId].bidder] += totalPrice;
        emit ClaimIncreased(auction.bids[bidId].bidder, totalPrice);
        emit BidLostNotification(tokenId, auctionId, bidId, auction.bids[bidId].bidder);
        if (idx == auction.revealedBidRoot) {
            auction.revealedBidRoot = auction.revealedBids[idx].right;
        } else {
            auction.revealedBids[idxParent].left = auction.revealedBids[idx].right;
        }
        delete(auction.revealedBids[idx]);
    }

    //This function calls the two helper functions to first place the newly 
    //revealed bid, then eliminate the out-bidded ones
    function revealBidOnAuction(address bidder, uint256 value, uint256 tokenId, uint64 auctionId, IBCEMusic.Auction storage auction, uint32 bidId, uint256 pricePerUnit, bytes32 nonce, mapping (address => uint256) storage withdrawalAllowances) external {
        require(auction.terms.amount > 0, "Invalid auction.");
        require(bidId <= auction.bids.length, "Invalid bid id.");
        require(block.timestamp > auction.terms.biddingDeadline, "Bidding has not yet closed.");
        require(block.timestamp <= auction.terms.revealingDeadline, "Revealing has closed.");
        
        IBCEMusic.Bid storage bid = auction.bids[bidId];
        require(bidder == bid.bidder, "Not your bid.");
        require((bid.amountAndRevealed & 0x80) == 0, "Duplicate revealing");
        require(pricePerUnit >= auction.terms.reservePricePerUnit, "Cannot reveal an invalid price.");
        uint256 totalPrice = pricePerUnit*(bid.amountAndRevealed & 0x7f);
        require(totalPrice <= value+bid.earnestMoney, "Not enough money to reveal.");

        bytes32 theHash = keccak256(abi.encodePacked((pricePerUnit ^ uint256(nonce)), bidder)); //because all three are fixed length types, encodePacked would be safe
        require(theHash == bid.bidHash, "Hash does not match.");

        _addRevealedBid(auction, bidId, pricePerUnit);

        bid.amountAndRevealed = (bid.amountAndRevealed | 0x80);
        if (value+bid.earnestMoney > totalPrice) {
            withdrawalAllowances[bidder] += value+bid.earnestMoney-totalPrice;
            emit ClaimIncreased(bidder, value+bid.earnestMoney-totalPrice);
            if (totalPrice < bid.earnestMoney) {
                auction.totalHeldBalance -= bid.earnestMoney-totalPrice;
            } else {
                auction.totalHeldBalance += totalPrice-bid.earnestMoney;
            }
        } else {
            auction.totalHeldBalance += value;
        }

        _eliminateOutBiddedRevealedBids(tokenId, auctionId, auction, withdrawalAllowances);
    }
    //This function build an array of all potentional winners from the 
    //currently kept linked-list of revealed bids, and it deletes all
    //the revealed bids since they are no longer needed
    function _buildPotentialWinners(IBCEMusic.Auction storage auction) private returns (IBCEMusic.AuctionWinner[] memory) {
        IBCEMusic.AuctionWinner[] memory potentialWinners = new IBCEMusic.AuctionWinner[](auction.totalInPlayRevealedBidCount);
        uint32[] memory stack = new uint32[](auction.totalInPlayRevealedBidCount);
        uint32 stackSize = 0;
        uint32 ii = 0;
        uint32 current = auction.revealedBidRoot;
        unchecked {
            while (stackSize > 0 || current != 0) {
                while (current != 0) {
                    stack[stackSize] = current;
                    ++stackSize;
                    current = auction.revealedBids[current].right;
                }
                if (stackSize > 0) {
                    current = stack[stackSize-1];
                    uint32 bidId = auction.revealedBids[current].bidId;
                    potentialWinners[ii] = IBCEMusic.AuctionWinner({
                        amount: (auction.bids[bidId].amountAndRevealed & 0x7f)
                        , bidId : bidId
                        , bidder : auction.bids[bidId].bidder
                        , pricePerUnit: auction.revealedBids[current].pricePerUnit
                        , refund: 0
                    });
                    ++ii;
                    current = auction.revealedBids[current].left;
                    delete(auction.revealedBids[stack[stackSize-1]]);
                    stack[stackSize-1] = 0;
                    --stackSize;
                }
            }
        }
        return potentialWinners;
    }
    //This function removes an auction from the double-linked list
    function _removeAuction(IBCEMusic.OutstandingAuctions storage auctions, uint64 auctionId, IBCEMusic.Auction storage auction) private returns (IBCEMusic.AuctionTerms memory) {
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

        IBCEMusic.AuctionTerms memory terms = auction.terms;
        delete(auctions.auctions[auctionId]);

        return terms;
    }
    struct AuctionResult {
        IBCEMusic.AuctionWinner[] winners;
        uint256 totalReceipt;
        IBCEMusic.AuctionTerms terms;
    }
    //This function calls the helper functions to prepare a winner's list 
    //(deleting all revealed bids on the way), and then deletes the auction
    //(but keeping a copy of the terms first). It then allocates the amounts
    //among the winners and calculates refunds.

    function finalizeAuction(uint256 tokenId, IBCEMusic.OutstandingAuctions storage auctions, uint64 auctionId) external returns (AuctionResult memory) {
        IBCEMusic.Auction storage auction = auctions.auctions[auctionId];
        require(auction.terms.amount > 0, "Invalid auction.");
        require(block.timestamp > auction.terms.revealingDeadline, "Immature finalizing");

        if (auction.revealedBidRoot == 0 || auction.totalInPlayRevealedBidCount == 0) {
            uint256 totalReceipt = auction.totalHeldBalance;
            IBCEMusic.AuctionTerms memory terms = _removeAuction(auctions, auctionId, auction);
            return AuctionResult({
                winners: new IBCEMusic.AuctionWinner[](0)
                , totalReceipt: totalReceipt
                , terms: terms
            });
        } else {
            IBCEMusic.AuctionWinner[] memory potentialWinners = _buildPotentialWinners(auction);
            uint256[] memory totalPay = new uint256[](potentialWinners.length);
            uint16 cumAmount = 0;
            uint16 totalAmount = auction.terms.amount;
            uint256 finalPrice = 0;
            uint256 finalReceipt = 0;
            uint16 cutOff = 0;
            unchecked {
                for (uint16 ii=0; ii<potentialWinners.length; ++ii) {
                    totalPay[ii] = potentialWinners[ii].pricePerUnit*potentialWinners[ii].amount;
                    uint256 p = 0;
                    if (ii+1 < potentialWinners.length) {
                        p = potentialWinners[ii+1].pricePerUnit;
                    } else {
                        p = auction.terms.reservePricePerUnit;
                    }
                    uint256 sz = 0;
                    for (int16 jj=int16(ii); jj>=0 /*&& sz<totalAmount*/; --jj) {
                        sz += totalPay[uint16(jj)]/p;
                    }
                    if (sz > totalAmount) {
                        sz = totalAmount;
                    }
                    if (finalReceipt < sz*p) {
                        finalReceipt = sz*p;
                        finalPrice = p;
                        cutOff = ii+1;
                    }
                    if (sz == totalAmount) {
                        break;
                    }
                }
            }
            for (uint16 ii=0; ii<cutOff; ++ii) {
                potentialWinners[ii].pricePerUnit = finalPrice;
                potentialWinners[ii].amount = uint16(Math.min(totalPay[ii]/finalPrice, uint256(totalAmount-cumAmount)));
                potentialWinners[ii].refund = totalPay[ii]-potentialWinners[ii].amount*potentialWinners[ii].pricePerUnit;
                if (potentialWinners[ii].amount > 0) {
                    emit BidWonNotification(tokenId, auctionId, potentialWinners[ii].bidId, potentialWinners[ii].amount, potentialWinners[ii].pricePerUnit, potentialWinners[ii].bidder);
                } else {
                    emit BidLostNotification(tokenId, auctionId, potentialWinners[ii].bidId, potentialWinners[ii].bidder);
                }
                cumAmount += potentialWinners[ii].amount;
            }
            for (uint16 ii=cutOff; ii<potentialWinners.length; ++ii) {
                potentialWinners[ii].amount = 0;
                potentialWinners[ii].refund = totalPay[ii];
                emit BidLostNotification(tokenId, auctionId, potentialWinners[ii].bidId, potentialWinners[ii].bidder);
            }

            uint256 totalReceipt = auction.totalHeldBalance;
            IBCEMusic.AuctionTerms memory terms = _removeAuction(auctions, auctionId, auction);

            return AuctionResult({
                winners: potentialWinners
                , totalReceipt: totalReceipt
                , terms: terms
            });
        }
    }
    function getAuctionById(IBCEMusic.OutstandingAuctions storage auctions, uint64 auctionId) external view returns (IBCEMusic.AuctionTerms memory) {
        require (auctionId > 0, "Invalid auction id.");
        IBCEMusic.AuctionTerms memory theTermsCopy = auctions.auctions[auctionId].terms;
        return theTermsCopy;
    }
    function getAllAuctions(IBCEMusic.OutstandingAuctions storage auctions) external view returns (IBCEMusic.AuctionTerms[] memory) {
        if (auctions.totalCount == 0) {
            return new IBCEMusic.AuctionTerms[](0);
        }
        IBCEMusic.AuctionTerms[] memory theTerms = new IBCEMusic.AuctionTerms[](auctions.totalCount);
        uint64 id = auctions.firstAuctionId;
        uint outputIdx = 0;
        while (id != 0 && outputIdx < theTerms.length) {
            IBCEMusic.Auction storage o = auctions.auctions[id];
            theTerms[outputIdx] = o.terms;
            unchecked {
                ++outputIdx;
            }
            id = o.nextAuction;
        }
        return theTerms;
    }
}
