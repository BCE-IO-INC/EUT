#include <vector>
#include <iostream>
#include <limits>
#include <random>
#include <chrono>
#include <tuple>
#include <stdint.h>

namespace algorithm_mock {
    struct InputDataItem {
        uint32_t price; //for C++ mock purposes, we limit price to uint32_t and we assume price*minUnits fits in uint64_t
        uint16_t minUnits;
    };
    using InputData = std::vector<InputDataItem>;

    template <typename T>
    concept PricingAlgorithm = requires(InputData const &input, uint32_t reservePrice, uint16_t totalUnits)
    {
        {T::price(input, reservePrice, totalUnits)} -> std::convertible_to<uint32_t>;
    };

    class NoncePricingAlgorithm {
    public:
        static uint32_t price(InputData const &input, uint32_t reservePrice, uint16_t totalUnits) {
            return 0;
        }
    };

    class PlainPricingAlgorithm {
    public:
        static uint32_t price(InputData const &input, uint32_t reservePrice, uint16_t totalUnits) {
            auto ll = input.size();
            uint64_t max = 0;
            uint32_t retVal = 0;
	    std::vector<uint64_t> totalP(ll);
            for (std::size_t ii=0; ii<ll; ++ii) {
                totalP[ii] = (uint64_t) input[ii].price*input[ii].minUnits;
                uint32_t p = (ii<ll-1)?input[ii+1].price:reservePrice;
                uint16_t sz = 0;
                for (std::size_t jj=0; jj<=ii; ++jj) {
                    sz += (uint32_t) (totalP[jj]/p);
                    if (sz >= totalUnits) {
                        sz = totalUnits;
                        break;
                    }
                }
                uint64_t revenue = sz*p;
                if (revenue > max) {
                    max = revenue;
                    retVal = p;
                }
                //std::cerr << '\t' << ii << ' ' << p << ' ' << sz << ' ' << p*sz << '\n';
                if (sz == totalUnits) {
                    break;
                }
            }
            return retVal;
        }
    };

    class BSTPricingAlgorithm {
    private:
        struct Treap {
            struct Node {
                uint64_t value = 0;
                int weight = 0;
                std::size_t count = 0;
                std::size_t subtreeSize = 0;
                std::size_t parent = std::numeric_limits<std::size_t>::max();
                std::size_t left = std::numeric_limits<std::size_t>::max();
                std::size_t right = std::numeric_limits<std::size_t>::max();
                std::size_t prev = std::numeric_limits<std::size_t>::max();
                std::size_t next = std::numeric_limits<std::size_t>::max();
            };
            std::vector<Node> nodes;
            InputData const *input;
            std::size_t insertIdx;
            std::size_t head;
            uint64_t maxVal = 0;

            std::random_device rd;
            std::mt19937 gen;
            std::uniform_int_distribution<int> dist;

            Treap(InputData const &_input) : 
                nodes(_input.size()), input(&_input), insertIdx(0), head(0) 
                , rd(), gen(rd()), dist(std::numeric_limits<int>::min(), std::numeric_limits<int>::max())
            {}

            void printNodes(std::ostream &os) {
                os << '[';
                for (auto ii=0; ii<insertIdx; ++ii) {
                    os << "{Value=" << nodes[ii].value 
                        << ",Weight=" << nodes[ii].weight 
                        << ",Count=" << nodes[ii].count 
                        << ",SubtreeSize=" << nodes[ii].subtreeSize 
                        << ",Parent=" << nodes[ii].parent 
                        << ",Left=" << nodes[ii].left 
                        << ",Right=" << nodes[ii].right 
                        << ",Prev=" << nodes[ii].prev 
                        << ",Next=" << nodes[ii].next
                        << "}  ";
                }
                os << "]\n";
            }

            void rotateUpForAdd(std::size_t idx) {
                auto p = idx;
                while (p != std::numeric_limits<std::size_t>::max() && nodes[p].weight < nodes[insertIdx].weight) {
                    if (nodes[p].right == insertIdx) {
                        auto l = nodes[insertIdx].left;
                        nodes[insertIdx].left = p;
                        nodes[p].right = l;
                        if (l != std::numeric_limits<std::size_t>::max()) {
                            nodes[l].parent = p;
                        }
                        nodes[p].subtreeSize = 
                                    nodes[p].subtreeSize = 
                        nodes[p].subtreeSize = 
                            ((nodes[p].left == std::numeric_limits<std::size_t>::max())?0:nodes[nodes[p].left].subtreeSize)
                            +nodes[p].count
                            +((nodes[p].right == std::numeric_limits<std::size_t>::max())?0:nodes[nodes[p].right].subtreeSize)
                            ;
                        nodes[insertIdx].parent = nodes[p].parent;
                        nodes[insertIdx].subtreeSize = 
                                    nodes[insertIdx].subtreeSize = 
                        nodes[insertIdx].subtreeSize = 
                            nodes[p].subtreeSize
                            +nodes[insertIdx].count
                            +((nodes[insertIdx].right == std::numeric_limits<std::size_t>::max())?0:nodes[nodes[insertIdx].right].subtreeSize)
                            ;
                        nodes[p].parent = insertIdx;
                        auto lastP = p;
                        p = nodes[insertIdx].parent;
                        if (p == std::numeric_limits<std::size_t>::max()) {
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
                        auto r = nodes[insertIdx].right;
                        nodes[insertIdx].right = p;
                        nodes[p].left = r;
                        if (r != std::numeric_limits<std::size_t>::max()) {
                            nodes[r].parent = p;
                        }
                        nodes[p].subtreeSize = 
                                    nodes[p].subtreeSize = 
                        nodes[p].subtreeSize = 
                            ((nodes[p].left == std::numeric_limits<std::size_t>::max())?0:nodes[nodes[p].left].subtreeSize)
                            +nodes[p].count
                            +((nodes[p].right == std::numeric_limits<std::size_t>::max())?0:nodes[nodes[p].right].subtreeSize)
                            ;
                        nodes[insertIdx].parent = nodes[p].parent;
                        nodes[insertIdx].subtreeSize = 
                                    nodes[insertIdx].subtreeSize = 
                        nodes[insertIdx].subtreeSize = 
                            nodes[p].subtreeSize
                            +nodes[insertIdx].count
                            +((nodes[insertIdx].left == std::numeric_limits<std::size_t>::max())?0:nodes[nodes[insertIdx].left].subtreeSize)
                            ;
                        nodes[p].parent = insertIdx;
                        auto lastP = p;
                        p = nodes[insertIdx].parent;
                        if (p == std::numeric_limits<std::size_t>::max()) {
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
                nodes[insertIdx] = {
                    .value = (*input)[insertIdx].price*(*input)[insertIdx].minUnits
                    , .weight = dist(gen)
                    , .count = 1
                    , .subtreeSize = 1
                };
                if (nodes[insertIdx].value > maxVal) {
                    maxVal = nodes[insertIdx].value;
                }
                if (insertIdx == 0) {
                    ++insertIdx;
                    return;
                }
                
                auto idx = head;
                while (true) {
                    if (nodes[idx].value == nodes[insertIdx].value) {
                        ++nodes[idx].count;
                        ++nodes[idx].subtreeSize;
                        auto p = nodes[idx].parent;
                        while (p != std::numeric_limits<std::size_t>::max()) {
                            ++nodes[p].subtreeSize;
                            p = nodes[p].parent;
                        }
                        break;
                    } else if (nodes[idx].value < nodes[insertIdx].value) {
                        if (nodes[idx].right == std::numeric_limits<std::size_t>::max()) {
                            nodes[idx].right = insertIdx;
                            nodes[insertIdx].parent = idx;
                            ++nodes[idx].subtreeSize;
                            nodes[insertIdx].prev = idx;
                            auto prevN = nodes[idx].next;
                            nodes[insertIdx].next = prevN;
                            nodes[idx].next = insertIdx;
                            if (prevN != std::numeric_limits<std::size_t>::max()) {
                                nodes[prevN].prev = insertIdx;
                            }
                            auto p = nodes[idx].parent;
                            while (p != std::numeric_limits<std::size_t>::max()) {
                                ++nodes[p].subtreeSize;
                                p = nodes[p].parent;
                            }
                            rotateUpForAdd(idx);
                            break;
                        } else {
                            idx = nodes[idx].right;
                        }
                    } else {
                        if (nodes[idx].left == std::numeric_limits<std::size_t>::max()) {
                            nodes[idx].left = insertIdx;
                            nodes[insertIdx].parent = idx;
                            ++nodes[idx].subtreeSize;
                            nodes[insertIdx].next = idx;
                            auto prevP = nodes[idx].prev;
                            nodes[insertIdx].prev = prevP;
                            nodes[idx].prev = insertIdx;
                            if (prevP != std::numeric_limits<std::size_t>::max()) {
                                nodes[prevP].next = insertIdx;
                            }
                            auto p = nodes[idx].parent;
                            while (p != std::numeric_limits<std::size_t>::max()) {
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
            std::tuple<std::size_t, std::size_t> findSmallestIdxGEAndSizeBelow(uint64_t val) {
                auto idx = head;
                auto candidate = std::numeric_limits<std::size_t>::max();
                auto sz = 0;
                while (true) {
                    if (nodes[idx].value == val) {
                        if (nodes[idx].left != std::numeric_limits<std::size_t>::max()) {
                            sz += nodes[nodes[idx].left].subtreeSize;
                        }
                        return {idx, sz};
                    }
                    if (nodes[idx].value < val) {
                        sz += nodes[idx].count;
                        if (nodes[idx].left != std::numeric_limits<std::size_t>::max()) {
                            sz += nodes[nodes[idx].left].subtreeSize;
                        }
                        idx = nodes[idx].right;
                        if (idx == std::numeric_limits<std::size_t>::max()) {
                            return {candidate, sz};
                        }
                    } else {
                        if (nodes[idx].left == std::numeric_limits<std::size_t>::max()) {
                            return {idx, sz};
                        }
                        candidate = idx;
                        idx = nodes[idx].left;
                    }
                }
                return {candidate, sz};
            }
            uint16_t totalSize(uint32_t p, uint32_t totalUnits) {
                auto sz = maxVal/p;
                if (sz >= totalUnits) {
                    return totalUnits;
                }
                auto cumSz = 0;
                auto rightCount = insertIdx;
                while (true) {
                    auto [left, leftCount] = findSmallestIdxGEAndSizeBelow(sz*p);
                    cumSz += sz*(rightCount-leftCount);
                    if (cumSz >= totalUnits) {
                        return totalUnits;
                    }
                    rightCount = leftCount;
                    if (left != std::numeric_limits<std::size_t>::max()) {
                        left = nodes[left].prev;
                    }
                    if (left == std::numeric_limits<std::size_t>::max()) {
                        return cumSz;
                    } else {
                        sz = nodes[left].value/p;
                    }
                }
                return cumSz;
            }
        };
    public:
        static uint32_t price(InputData const &input, uint32_t reservePrice, uint16_t totalUnits) {
            Treap tr(input);
            auto ll = input.size();
            uint64_t max = 0;
            uint32_t retVal = 0;
            for (auto ii=0; ii<ll; ++ii) {
                tr.add();
                auto p = (ii==ll-1)?reservePrice:input[ii+1].price;
                auto sz = tr.totalSize(p, totalUnits);
                //std::cerr << '\t' << ii << ' ' << p << ' ' << sz << ' ' << p*sz << '\n';
                if (p*sz > max) {
                    max = p*sz;
                    retVal = p;
                }
                if (sz == totalUnits) {
                    break;
                }
            }
            return retVal;
        }
    };
}

template <algorithm_mock::PricingAlgorithm Alg>
void test(algorithm_mock::InputData const &input, uint32_t reservePrice, uint16_t totalUnits) {
    auto t1 = std::chrono::steady_clock::now();
    auto v = Alg::price(input, reservePrice, totalUnits);
    auto t2 = std::chrono::steady_clock::now();
    std::cout << v << ' ' << std::chrono::duration_cast<std::chrono::microseconds>(t2-t1).count() << '\n';
}

int main() {
    algorithm_mock::InputData input;
    for (int ii=0; ii<=500; ++ii) {
        input.push_back(algorithm_mock::InputDataItem {
            .price = (uint32_t) (600-ii)
            , .minUnits = (uint16_t) 1
        });
    } 
    std::sort(input.begin(), input.end(), [](auto const &a, auto const &b) {
            return b.price < a.price;
    });
    test<algorithm_mock::PlainPricingAlgorithm>(input, 100, 500);
    test<algorithm_mock::BSTPricingAlgorithm>(input, 100, 500);
    return 0;
}
