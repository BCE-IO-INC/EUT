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
function asUint96ByteArray(x) {
    const n = ethers.BigNumber.from(x);
    const arr = ethers.utils.arrayify(n);
    var ret = new Uint8Array(12);
    for (var ii=0; ii<arr.length; ++ii) {
        ret[12-arr.length+ii] = arr[ii];
    }
    return ret;
}
function asByte12String(x) {
    return ethers.utils.hexlify(asUint96ByteArray(x));
}

function bidHash(price, nonce, address) {
    const y = [
        asUint256ByteArray(price)
        , asUint96ByteArray(nonce)
        , ethers.utils.arrayify(ethers.BigNumber.from(address))
    ];
    var arr = new Uint8Array(y[0].length+y[1].length+y[2].length);
    arr.set(y[0]);
    arr.set(y[1], y[0].length);
    arr.set(y[2], y[0].length+y[1].length);
    console.log(arr);
    return ethers.utils.keccak256(arr);
}

console.log(bidHash(100, 10, "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2"));
console.log(bidHash(120, 10, "0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db"));
console.log(asByte12String(10));