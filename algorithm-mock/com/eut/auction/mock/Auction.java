package com.eut.auction.mock;

import java.math.BigDecimal;

//这个类的总体写法是为将来上链考虑的，所以基本没有使用
//Java的各种数据结构，也不使用递归

public class Auction {

    public static class OneAuctionInput {
        //Java没有unsigned类型，只能都用signed来代替
        BigDecimal price; //最高愿意出的每单元价格。这个在solidity里大约会是uint256，这里改成BigDecimal
        short requestUnits; //要求买的单元数。由于我们最多卖500单元，所以short肯定是够的，到solidity里面就是uint16

        OneAuctionInput(BigDecimal p, short u) {
            this.price = p;
            this.requestUnits = u;
        }
    }

    //朴素定价算法
    //输出的结果是最后的每单元拍卖价
    public static BigDecimal plainPricing(
        OneAuctionInput[] input //所有还没有被退回的买单
                                //上链的话，应该会在每新有一个买单揭晓的时候退掉已经不可能买到（即排在前面的单，即使去掉最后一个，总要求单元数也已经超过了总量）的单，这样的话，可以确保这里的输入数组长度不超过总量
                                //输入的时候这个数组必须按单元价格从高到低排序（同样价格按下单顺序排）。实测这个排序的要求即使在链上也是可以做到的。这里没有加assert，但如果不满足的话，结果会是错误的。
        , BigDecimal reservePrice      //每单元保留价格，数组里的每一个的单元价格都必须不小于这个价格（也没有加assert）
        , short totalUnits      //总量
    ) {
        var ll = input.length;
        BigDecimal max = BigDecimal.ZERO;
        BigDecimal retVal = BigDecimal.ZERO;
	    BigDecimal[] totalP = new BigDecimal[ll];
        for (var ii=0; ii<ll; ++ii) {
            totalP[ii] = input[ii].price.multiply(BigDecimal.valueOf(input[ii].requestUnits));
            var p = (ii<ll-1)?input[ii+1].price:reservePrice;
            long sz = 0;
            //输入排序的重要性在这里
            //这样保证了每次只有排序靠前的单才会被考虑使用这个价格匹配
            for (var jj=0; jj<=ii; ++jj) {
                sz += totalP[jj].divideToIntegralValue(p).longValue();
                if (sz >= totalUnits) {
                    sz = totalUnits;
                    break;
                }
            }
            var revenue = BigDecimal.valueOf(sz).multiply(p);
            if (revenue.compareTo(max) > 0) {
                max = revenue;
                retVal = p;
            }
            if (sz == totalUnits) {
                break;
            }
        }
        return retVal;
    }

    //复杂定价算法，输入输出与朴素算法相同
    public static BigDecimal bstPricing(
        OneAuctionInput[] input 
        , BigDecimal reservePrice
        , short totalUnits
    ) {
        //这是一个二叉树节点结构，value代表一个买单的总金额（单元价格*要求单元数），
        //weight是随机数用来保持二叉树平衡，count是该节点上同样的买单数量，
        //subtreeSize是包括该节点本身以该节点为根的字数中所有的买单数量。

        //在Java实现中，随机数是在创建树节点时产生的，如果要上链，随机数应该是输入
        //的一部分（每个买单对应的block hash即可）。
        class Node {
            BigDecimal value = BigDecimal.ZERO;
            int weight = 0;
            short count = 0;
            short subtreeSize = 0;
            int parent = Integer.MAX_VALUE;
            int left = Integer.MAX_VALUE;
            int right = Integer.MAX_VALUE;
            int prev = Integer.MAX_VALUE;
            int next = Integer.MAX_VALUE;
        }
        //为了不使用过于新的Java feature，这里单独定义一个数据结构用作Treap的
        //一个方法返回类型。
        class IdxAndSizeBelow {
            int idx;
            short sizeBelow;

            IdxAndSizeBelow(int idx, short sizeBelow) {
                this.idx = idx;
                this.sizeBelow = sizeBelow;
            }
        }
        class Treap {
            Node[] nodes;
            OneAuctionInput[] input;
            int insertIdx;
            int head;
            BigDecimal maxVal;

            Treap(OneAuctionInput[] input) {
                this.nodes = new Node[input.length];
                this.input = input;
                this.insertIdx = 0;
                this.head = 0;
                this.maxVal = BigDecimal.ZERO;
            }

            void rotateUpForAdd(int idx) {
                var p = idx;
                while (p != Integer.MAX_VALUE && nodes[p].weight < nodes[insertIdx].weight) {
                    if (nodes[p].right == insertIdx) {
                        var l = nodes[insertIdx].left;
                        nodes[insertIdx].left = p;
                        nodes[p].right = l;
                        if (l != Integer.MAX_VALUE) {
                            nodes[l].parent = p;
                        }
                        nodes[p].subtreeSize = 
                            (short) (
                                ((nodes[p].left == Integer.MAX_VALUE)?(short) 0:nodes[nodes[p].left].subtreeSize)
                                +nodes[p].count
                                +((nodes[p].right == Integer.MAX_VALUE)?(short) 0:nodes[nodes[p].right].subtreeSize)
                            );
                        nodes[insertIdx].parent = nodes[p].parent;
                        nodes[insertIdx].subtreeSize = 
                            (short) (
                                nodes[p].subtreeSize
                                +nodes[insertIdx].count
                                +((nodes[insertIdx].right == Integer.MAX_VALUE)?(short) 0:nodes[nodes[insertIdx].right].subtreeSize)
                            );
                        nodes[p].parent = insertIdx;
                        var lastP = p;
                        p = nodes[insertIdx].parent;
                        if (p == Integer.MAX_VALUE) {
                            head = insertIdx;
                            break;
                        } else {
                            if (nodes[p].left == lastP) {
                                nodes[p].left = insertIdx;
                            } else {
                                nodes[p].right = insertIdx;
                            }
                        }
                    } else {
                        var r = nodes[insertIdx].right;
                        nodes[insertIdx].right = p;
                        nodes[p].left = r;
                        if (r != Integer.MAX_VALUE) {
                            nodes[r].parent = p;
                        }
                        nodes[p].subtreeSize = 
                            (short) (
                                ((nodes[p].left == Integer.MAX_VALUE)?(short) 0:nodes[nodes[p].left].subtreeSize)
                                +nodes[p].count
                                +((nodes[p].right == Integer.MAX_VALUE)?(short) 0:nodes[nodes[p].right].subtreeSize)
                            );
                        nodes[insertIdx].parent = nodes[p].parent;
                        nodes[insertIdx].subtreeSize = 
                            (short) (
                                nodes[p].subtreeSize
                                +nodes[insertIdx].count
                                +((nodes[insertIdx].left == Integer.MAX_VALUE)?(short) 0:nodes[nodes[insertIdx].left].subtreeSize)
                            );
                        nodes[p].parent = insertIdx;
                        var lastP = p;
                        p = nodes[insertIdx].parent;
                        if (p == Integer.MAX_VALUE) {
                            head = insertIdx;
                            break;
                        } else {
                            if (nodes[p].left == lastP) {
                                nodes[p].left = insertIdx;
                            } else {
                                nodes[p].right = insertIdx;
                            }
                        }
                    }
                }
            }
            void add() {
                var n = new Node();
                n.value = input[insertIdx].price.multiply(BigDecimal.valueOf(input[insertIdx].requestUnits));
                n.weight = java.util.concurrent.ThreadLocalRandom.current().nextInt(0, 1000000);
                n.count = 1;
                n.subtreeSize = 1;
                nodes[insertIdx] = n;
                if (nodes[insertIdx].value.compareTo(maxVal) > 0) {
                    maxVal = nodes[insertIdx].value;
                }
                if (insertIdx == 0) {
                    ++insertIdx;
                    return;
                }
                
                var idx = head;
                while (true) {
                    if (nodes[idx].value.compareTo(nodes[insertIdx].value) == 0) {
                        ++nodes[idx].count;
                        ++nodes[idx].subtreeSize;
                        var p = nodes[idx].parent;
                        while (p != Integer.MAX_VALUE) {
                            ++nodes[p].subtreeSize;
                            p = nodes[p].parent;
                        }
                        break;
                    } else if (nodes[idx].value.compareTo(nodes[insertIdx].value) < 0) {
                        if (nodes[idx].right == Integer.MAX_VALUE) {
                            nodes[idx].right = insertIdx;
                            nodes[insertIdx].parent = idx;
                            ++nodes[idx].subtreeSize;
                            nodes[insertIdx].prev = idx;
                            var prevN = nodes[idx].next;
                            nodes[insertIdx].next = prevN;
                            nodes[idx].next = insertIdx;
                            if (prevN != Integer.MAX_VALUE) {
                                nodes[prevN].prev = insertIdx;
                            }
                            var p = nodes[idx].parent;
                            while (p != Integer.MAX_VALUE) {
                                ++nodes[p].subtreeSize;
                                p = nodes[p].parent;
                            }
                            rotateUpForAdd(idx);
                            break;
                        } else {
                            idx = nodes[idx].right;
                        }
                    } else {
                        if (nodes[idx].left == Integer.MAX_VALUE) {
                            nodes[idx].left = insertIdx;
                            nodes[insertIdx].parent = idx;
                            ++nodes[idx].subtreeSize;
                            nodes[insertIdx].next = idx;
                            var prevP = nodes[idx].prev;
                            nodes[insertIdx].prev = prevP;
                            nodes[idx].prev = insertIdx;
                            if (prevP != Integer.MAX_VALUE) {
                                nodes[prevP].next = insertIdx;
                            }
                            var p = nodes[idx].parent;
                            while (p != Integer.MAX_VALUE) {
                                ++nodes[p].subtreeSize;
                                p = nodes[p].parent;
                            }
                            rotateUpForAdd(idx);
                            break;
                        } else {
                            idx = nodes[idx].left;
                        }
                    }
                }
                ++insertIdx;
            }
            IdxAndSizeBelow findSmallestIdxGEAndSizeBelow(BigDecimal val) {
                var idx = head;
                var candidate = Integer.MAX_VALUE;
                var sz = 0;
                while (true) {
                    if (nodes[idx].value.compareTo(val) == 0) {
                        if (nodes[idx].left != Integer.MAX_VALUE) {
                            sz += nodes[nodes[idx].left].subtreeSize;
                        }
                        return new IdxAndSizeBelow(idx, (short) sz);
                    }
                    if (nodes[idx].value.compareTo(val) < 0) {
                        sz += nodes[idx].count;
                        if (nodes[idx].left != Integer.MAX_VALUE) {
                            sz += nodes[nodes[idx].left].subtreeSize;
                        }
                        idx = nodes[idx].right;
                        if (idx == Integer.MAX_VALUE) {
                            return new IdxAndSizeBelow(candidate, (short) sz);
                        }
                    } else {
                        if (nodes[idx].left == Integer.MAX_VALUE) {
                            return new IdxAndSizeBelow(idx, (short) sz);
                        }
                        candidate = idx;
                        idx = nodes[idx].left;
                    }
                }
            }
            short totalSize(BigDecimal p, short totalUnits) {
                long sz = maxVal.divideToIntegralValue(p).longValue();
                if (sz >= totalUnits) {
                    return totalUnits;
                }
                int cumSz = 0;
                var rightCount = insertIdx;
                while (true) {
                    var idxAndSizeBelow = findSmallestIdxGEAndSizeBelow(BigDecimal.valueOf(sz).multiply(p));
                    var left = idxAndSizeBelow.idx;
                    var leftCount = idxAndSizeBelow.sizeBelow;
                    cumSz += sz*(rightCount-leftCount);
                    if (cumSz >= totalUnits) {
                        return totalUnits;
                    }
                    rightCount = leftCount;
                    if (left != Integer.MAX_VALUE) {
                        left = nodes[left].prev;
                    }
                    if (left == Integer.MAX_VALUE) {
                        return (short) cumSz;
                    } else {
                        sz = nodes[left].value.divideToIntegralValue(p).longValue();
                    }
                }
            }
        }

        Treap tr = new Treap(input);
        var ll = input.length;
        BigDecimal max = BigDecimal.ZERO;
        BigDecimal retVal = BigDecimal.ZERO;
        for (var ii=0; ii<ll; ++ii) {
            tr.add();
            var p = (ii==ll-1)?reservePrice:input[ii+1].price;
            var sz = tr.totalSize(p, totalUnits);
            var revenue = p.multiply(BigDecimal.valueOf(sz));
            if (revenue.compareTo(max) > 0) {
                max = revenue;
                retVal = p;
            }
            if (sz == totalUnits) {
                break;
            }
        }
        return retVal;
    }

    //这一方法把单元根据最终算出的价格分配给各个买单
    //算法很简单：从单价高的往下分配，分完为止
    public static short[] assignUnits(
        OneAuctionInput[] input 
        , BigDecimal auctionPrice //这是定价算法算出的结果
        , short totalUnits
    ) {
        short[] retVal = new short[input.length];
        short remaining = totalUnits;
        int idx = 0;
        while (remaining > 0) {
            long sz = (input[idx].price.multiply(BigDecimal.valueOf(input[idx].requestUnits))).divideToIntegralValue(auctionPrice).longValue();
            if (sz >= remaining) {
                retVal[idx] = remaining;
                remaining = 0;
            } else {
                retVal[idx] = (short) sz;
                remaining -= (short) sz;
            }
            ++idx;
        }
        while (idx < retVal.length) {
            retVal[idx] = 0;
            ++idx;
        }
        return retVal;
    }

    //改为BigDecimal之后，Java实现的结果是500尺度下复杂算法已经比朴素算法占优。
    public static void main(String[] args) {
        OneAuctionInput[] input = new OneAuctionInput[501];
        for (var ii=0; ii<=500; ++ii) {
            input[ii] = new OneAuctionInput(BigDecimal.valueOf(600-ii), (short) 1);
        }
        long s = System.nanoTime();
        var v = plainPricing(input, BigDecimal.valueOf(100), (short) 500);
        long e = System.nanoTime();
        System.out.println("plain: "+v+" "+(e-s));
        s = System.nanoTime();
        v = bstPricing(input, BigDecimal.valueOf(100), (short) 500);
        e = System.nanoTime();
        System.out.println("bst: "+v+" "+(e-s));
    }
}