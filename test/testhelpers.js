const {ethers} = require('ethers')

function asUint256ByteArray(x) {
    const n = ethers.BigNumber.from(x);
    const arr = ethers.utils.arrayify(n);
    var ret = new Uint8Array(32);
    for (var ii=0; ii<arr.length; ++ii) {
        ret[32-arr.length+ii] = arr[ii];
    }
    return ret;
}
function asByte32String(x) {
    return ethers.utils.hexlify(asUint256ByteArray(x));
}

function bidHash(price, nonce, address) {
    const y = [
        asUint256ByteArray(price)
        , asUint256ByteArray(nonce)
        , ethers.utils.arrayify(ethers.BigNumber.from(address))
    ];
    var arr = new Uint8Array(y[0].length+y[1].length+y[2].length);
    arr.set(y[0]);
    arr.set(y[1], y[0].length);
    arr.set(y[2], y[0].length+y[1].length);
    return ethers.utils.keccak256(arr);
}

console.log(bidHash(1000, 10, "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2"));
console.log(asByte32String(10));