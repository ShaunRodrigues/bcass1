import { ethers } from "ethers";
import fs from "fs";

// ========= CONFIG =========
const RPC_URL = "https://sepolia.infura.io/v3/"; // or Anvil/Ganache URL
const OWNER_PRIVATE_KEY = ""; // the factory owner key (for creating elections)

const FACTORY_ADDRESS = "0xf845070b31c2baebd23f83ec51bdd068182a5add"; // your deployed factory
const REGISTRY_ADDRESS = "0xe31b87504cbbe563a6c3a3c98d8cf76bfb78ec20"; // your deployed factory

// === Load ABIs ===
const factoryAbi = JSON.parse(fs.readFileSync("./artifacts/ElectionFactory.json")).abi;
const fptpAbi   = JSON.parse(fs.readFileSync("./artifacts/FPTPElection.json")).abi;
const irvAbi    = JSON.parse(fs.readFileSync("./artifacts/IRVElection.json")).abi;
const bordaAbi  = JSON.parse(fs.readFileSync("./artifacts/BordaElection.json")).abi;
const condAbi   = JSON.parse(fs.readFileSync("./artifacts/CondorcetElection.json")).abi;
const prAbi     = JSON.parse(fs.readFileSync("./artifacts/PRElectionDhondt.json")).abi;

// If you know the registry address up front, you can set it here.
// Otherwise we’ll read it from the election after creation via election.registry().
const registryAbi = JSON.parse(fs.readFileSync("./artifacts/VoterRegistry.json")).abi;

// ========= SETUP =========
const provider = new ethers.JsonRpcProvider(RPC_URL);
const owner = new ethers.Wallet(OWNER_PRIVATE_KEY, provider);
const factory = new ethers.Contract(FACTORY_ADDRESS, factoryAbi, owner);

// ========= UTILITIES =========

// Parse a specific event from a transaction receipt
function findEvent(receipt, iface, name) {
  for (const log of receipt.logs) {
    try {
      const parsed = iface.parseLog(log);
      if (parsed && parsed.name === name) return parsed;
    } catch {}
  }
  return null;
}

// Sleep (ms)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Encode ballots (per election type)

const encodeBallot = (rankingArray /* uint8[] */) =>
  ethers.AbiCoder.defaultAbiCoder().encode(["uint8[]"], [rankingArray]);

// Compute commit hash = keccak256(abi.encodePacked(election, ballotEncoded, salt, secret))
function computeCommit(electionAddress, ballotEncoded, secret32) {
  return ethers.solidityPackedKeccak256(
    ["address", "bytes", "bytes32"],
    [electionAddress, ballotEncoded, secret32]
  );
}

// Generate a random bytes32 hex string
const rand32 = () => ethers.hexlify(ethers.randomBytes(32));

// Attach to a contract with a specific signer
const attach = (addr, abi, signer) => new ethers.Contract(addr, abi, signer);

// Read on-chain time deltas and wait appropriately (optional convenience)
async function waitUntilPhase(election, target /* "reveal" | "finalize" */) {
  const block = await provider.getBlock("latest");
  const now = BigInt(block.timestamp);

  const commitDeadline = await election.commitDeadline(); // uint64
  const revealDeadline = await election.revealDeadline(); // uint64
  const phase = await election.phase();
  if (target === "reveal") {
    if (now < commitDeadline) {
      const ms = Number(commitDeadline - now) * 1000 + 2000;
      console.log(`⏳ Waiting ~${Math.ceil(ms / 1000)}s for reveal phase...`);
      await sleep(ms);
    }else if(phase=="Commit")
    {
      const s =await election.advancePhase();
      await s.wait();
    }
  } else if (target === "finalize") {
    if (now < revealDeadline) {
      const ms = Number(revealDeadline - now) * 1000 + 2000;
      console.log(`⏳ Waiting ~${Math.ceil(ms / 1000)}s to finalize...`);
      await sleep(ms);
    }else if(phase=="Reveal")
    {
      const s =await election.advancePhase();
      await s.wait();
    }
  }
}


// ========= VOTER FLOW =========

// Register a voter *on the VoterRegistry* for a given election (must be called by the voter’s signer)
async function registerVoterForElection(voterSigner, electionAddress) {
  // discover registry from election
  const registry = attach(REGISTRY_ADDRESS, registryAbi, voterSigner);

  const tx = await registry.register(electionAddress);
  await tx.wait();
  console.log(`📝 Registered ${await voterSigner.getAddress()} for election ${electionAddress}`);
}

// Commit a ballot for FPTP (same pattern for other methods)
async function commitBallot(voterSigner, abi, electionAddress, choiceArray, secret) {
  const election = attach(electionAddress, abi, voterSigner);

  const ballotEncoded = encodeBallot(choiceArray);
  /*let password = prompt("Enter your password:");
  console.log("Here, " + password);
  const secret = password;*/

  const comHash = computeCommit(electionAddress, ballotEncoded, secret);
  const tx = await election.commit(comHash);
  await tx.wait();

  console.log(`🔒 Commit from ${await voterSigner.getAddress()} (choice=${choiceArray})`);
  return { ballotEncoded };
}

async function revealBallot(voterSigner, abi = fptpAbi, electionAddress, ballotEncoded, secret) {
  const election = attach(electionAddress, abi, voterSigner);
  const tx = await election.reveal(ballotEncoded, secret);
  await tx.wait();
  console.log(`🔓 Reveal from ${await voterSigner.getAddress()}`);
}

// ========= DEMO (FPTP end-to-end) =========

async function demoFPTP() {
  // 1) Create an election (owner)
  const candidates = [2, 3, 1, 0];
  let address = prompt("Enter your address:");
  console.log("Registering");
  await registerVoterForElection(signer, address);
  let password = prompt("Enter your password:");
  console.log("Here, " + password);
  let x = prompt("Start Vote?");
  console.log(`Voting ${candidates}`);
  let ss = await commitBallot(signer, fptpAbi, address, candidates, password);


  //const electionAddress = await createFPTP("Board Election", commitDeadline, revealDeadline, candidates);

  // 2) Prepare three voters (you need their private keys funded with ETH if on a real network)
  // For demo: create random wallets (works best on a local dev chain)

  // 3) Each voter registers on the registry for THIS election

  // 4) Each voter commits (store their salts/secrets locally to reveal later)
  // 5) Wait for reveal phase
  await waitUntilPhase(attach(electionAddress, fptpAbi, signer), "reveal");
  revealBallot(signer, fptpAbi, address, ss, password);
  // 6) Reveal
  // 7) Finalize (anyone can do it after revealDeadline)
  console.log("Finalize");
  await waitUntilPhase(attach(electionAddress, fptpAbi, signer), "finalize");
  const tx = await attach(electionAddress, fptpAbi, signer).finalize();
  await tx.wait();

  // 8) Read winner (public state)
  const electionRead = attach(electionAddress, fptpAbi, signer);
  const winIdx = await electionRead.winner.call();
  const name = await electionRead.candidates(winIdx);
  console.log(`🏆 Winner index=${winIdx} (${name})`);
}

// ========= (Optional) Helpers for other methods =========
// Usage pattern is the same: register → commit (with proper encoding) → wait → reveal → finalize.
// Example commit for IRV:
//   const ballot = encodeBallotIRV([0,2,1]); // full ranking
//   const com = computeCommit(electionAddr, ballot, salt, secret);
//   await election.commit(com);
// And reveal with election.reveal(ballot, salt, secret) using the IRV ABI.

(async () => {
  try {
    await demoFPTP();
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
})();