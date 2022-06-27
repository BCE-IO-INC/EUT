const Web3 = require('web3');
const fs = require('fs');
const contract = require("@truffle/contract");
const util = require('node:util');
const _ = require('lodash');

const yargs = require('yargs/yargs')
const { hideBin } = require('yargs/helpers')
const argv = yargs(hideBin(process.argv)).argv

const { Level } = require('level');

async function runAsync() {
    const db = new Level('./ownership.db', {valueEncoding: 'json'});

    if (argv.purge) {
        await db.clear();
    } 

    var lastSeenBlockInDB = 0;
    
    try {
        lastSeenBlockInDB = await db.get("lastSeenBlock");
    } catch (_e) {
        lastSeenBlockInDB = 0;
    }

    console.log(`last seen block in db is ${lastSeenBlockInDB}`);

    const settingsContractArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusicSettings.json")); //produced by Truffle compile
    const SettingsContract = contract(settingsContractArtifact);

    const musicArtifact = JSON.parse(fs.readFileSync(__dirname+"/../build/contracts/BCEMusic.json")); //produced by Truffle compile
    const MusicContract = contract(musicArtifact);

    const provider = new Web3.providers.WebsocketProvider("ws://localhost:8545");
    const web3 = new Web3(provider);
    SettingsContract.setProvider(provider);
    MusicContract.setProvider(provider);

    const settingsContract = await SettingsContract.deployed();
    const result = await settingsContract.ownerFeePercentForAuction();
    console.log(`owner percent fee for auction = ${result.toNumber()}`);

    const musicContract = await MusicContract.deployed();
    const auctions = await musicContract.getAllAuctionsOnToken(2);
    console.log(`outstanding auctions on token 2 are ${util.inspect(auctions)}`);

    const accts = await web3.eth.getAccounts();

    musicContract.contract.events.allEvents({
        fromBlock: lastSeenBlockInDB+1
    })
        .on('data', (event) => {
            (async () => {
                if (event.event === 'OfferCreated' && event.blockNumber > lastSeenBlockInDB && event.returnValues.seller === accts[0]) {
                    console.log(`withdrawing offer ${event.returnValues.offerId}`);
                    musicContract.withdrawOffer(event.returnValues.tokenId, event.returnValues.offerId, {from: accts[0]});
                } else if (event.event === 'TransferSingle') {
                    var id = event.returnValues.id;
                    var from = event.returnValues.from;
                    var to = event.returnValues.to;
                    var value = event.returnValues.value;
                    if (new web3.utils.BN(from).toNumber() !== 0) {
                        const fromLevel = db.sublevel(from);
                        var v = 0;
                        try {
                            v = await fromLevel.get(id);
                        } catch (_e) {
                            v = 0;
                        }
                        v -= parseInt(value);
                        await fromLevel.put(id, v);
                    }
                    const toLevel = db.sublevel(to);
                    var v = 0;
                    try {
                        v = await toLevel.get(id);
                    } catch (_e) {
                        v = 0;
                    }
                    v += parseInt(value);
                    await toLevel.put(id, v);
                } else if (event.event === 'OfferWithdrawn' && event.blockNumber > lastSeenBlockInDB) {
                    console.log(`offer ${event.returnValues.offerId} withdrawn`);
                    for await (const [k, v] of db.iterator()) {
                        if (k !== 'lastSeenBlock') {
                            console.log(`Ownership: ${k} -- ${v}`);
                        }
                    }
                }
                await db.put('lastSeenBlock', event.blockNumber);
            })();
        });
    
    musicContract.offer(2, 10, 1000, {from: accts[0]});
}

runAsync();