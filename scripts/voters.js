// run-elections.js
// ESM: run with `node run-elections.js` (Node 18+)
// Make sure you have ethers v6 installed: `npm i ethers`
// And ABIs present at the given paths.

import { ethers } from "ethers";
import fs from "fs";

// ========= CONFIG =========
const RPC_URL = "https://sepolia.infura.io/v3/<YOUR_KEY>"; // or Anvil/Ganache URL
const OWNER_PRIVATE_KEY = ""; // the factory owner key (for creating elections)

const FACTORY_ADDRESS = "0x1885e87c6b4bc0916306cc7a2f9ec8ff63eede3d"; // your deployed factory

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
const encodeBallotFPTP = (choiceIndex) =>
  ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [choiceIndex]);

const encodeBallotIRV = (rankingArray /* uint8[] */) =>
  ethers.AbiCoder.defaultAbiCoder().encode(["uint8[]"], [rankingArray]);

const encodeBallotBorda = (rankingArray /* uint8[] */) =>
  ethers.AbiCoder.defaultAbiCoder().encode(["uint8[]"], [rankingArray]);

const encodeBallotCondorcet = (rankingArray /* uint8[] */) =>
  ethers.AbiCoder.defaultAbiCoder().encode(["uint8[]"], [rankingArray]);

const encodeBallotPR = (partyIndex /* uint256 */) =>
  ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [partyIndex]);

// Compute commit hash = keccak256(abi.encodePacked(election, ballotEncoded, salt, secret))
function computeCommit(electionAddress, ballotEncoded, salt32, secret32) {
  return ethers.solidityPackedKeccak256(
    ["address", "bytes", "bytes32", "bytes32"],
    [electionAddress, ballotEncoded, salt32, secret32]
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

  if (target === "reveal") {
    if (now < commitDeadline) {
      const ms = Number(commitDeadline - now) * 1000 + 2000;
      console.log(`⏳ Waiting ~${Math.ceil(ms / 1000)}s for reveal phase...`);
      await sleep(ms);
    }
  } else if (target === "finalize") {
    if (now < revealDeadline) {
      const ms = Number(revealDeadline - now) * 1000 + 2000;
      console.log(`⏳ Waiting ~${Math.ceil(ms / 1000)}s to finalize...`);
      await sleep(ms);
    }
  }
}

// ========= OWNER FLOW (create elections) =========

async function createFPTP(name, commitDeadline, revealDeadline, candidates) {
  console.log("Creating FPTP election...");
  const tx = await factory.createFPTP(name, commitDeadline, revealDeadline, candidates);
  const rcpt = await tx.wait();
  const ev = findEvent(rcpt, factory.interface, "FPTPCreated");
  if (!ev) throw new Error("FPTPCreated event not found");
  const election = ev.args.election;
  const id = ev.args.id; // bytes32
  console.log(`✅ FPTP created at ${election} (id: ${id})`);
  return election;
}

// (Similar creators for other methods, if you need them:)
async function createIRV(name, commitDeadline, revealDeadline, candidates) {
  const tx = await factory.createIRV(name, commitDeadline, revealDeadline, candidates);
  const rcpt = await tx.wait();
  const ev = findEvent(rcpt, factory.interface, "IRVCreated");
  if (!ev) throw new Error("IRVCreated event not found");
  return ev.args.election;
}

async function createBorda(name, commitDeadline, revealDeadline, candidates) {
  const tx = await factory.createBorda(name, commitDeadline, revealDeadline, candidates);
  const rcpt = await tx.wait();
  const ev = findEvent(rcpt, factory.interface, "BordaCreated");
  if (!ev) throw new Error("BordaCreated event not found");
  return ev.args.election;
}

async function createCondorcet(name, commitDeadline, revealDeadline, candidates) {
  const tx = await factory.createCondorcet(name, commitDeadline, revealDeadline, candidates);
  const rcpt = await tx.wait();
  const ev = findEvent(rcpt, factory.interface, "CondorcetCreated");
  if (!ev) throw new Error("CondorcetCreated event not found");
  return ev.args.election;
}

async function createPR(name, commitDeadline, revealDeadline, partyNames, seats, thresholdBps) {
  const tx = await factory.createPRDhondt(name, commitDeadline, revealDeadline, partyNames, seats, thresholdBps);
  const rcpt = await tx.wait();
  const ev = findEvent(rcpt, factory.interface, "PRCreated");
  if (!ev) throw new Error("PRCreated event not found");
  return ev.args.election;
}

// ========= VOTER FLOW =========

// Register a voter *on the VoterRegistry* for a given election (must be called by the voter’s signer)
async function registerVoterForElection(voterSigner, electionAddress) {
  // discover registry from election
  const election = attach(electionAddress, fptpAbi /* any election ABI with `registry()` */, voterSigner);
  const registryAddr = await election.registry();
  const registry = attach(registryAddr, registryAbi, voterSigner);

  const tx = await registry.register(electionAddress);
  await tx.wait();
  console.log(`📝 Registered ${await voterSigner.getAddress()} for election ${electionAddress}`);
}

// Commit a ballot for FPTP (same pattern for other methods)
async function commitBallotFPTP(voterSigner, electionAddress, choiceIndex, secrets) {
  const election = attach(electionAddress, fptpAbi, voterSigner);

  const ballotEncoded = encodeBallotFPTP(choiceIndex);
  const salt = secrets.salt ?? rand32();
  const secret = secrets.secret ?? rand32();

  const comHash = computeCommit(electionAddress, ballotEncoded, salt, secret);
  const tx = await election.commit(comHash);
  await tx.wait();

  console.log(`🔒 Commit from ${await voterSigner.getAddress()} (choice=${choiceIndex})`);
  return { ballotEncoded, salt, secret };
}

async function revealBallot(voterSigner, electionAddress, ballotEncoded, salt, secret, abi = fptpAbi) {
  const election = attach(electionAddress, abi, voterSigner);
  const tx = await election.reveal(ballotEncoded, salt, secret);
  await tx.wait();
  console.log(`🔓 Reveal from ${await voterSigner.getAddress()}`);
}

// ========= DEMO (FPTP end-to-end) =========

async function demoFPTP() {
  // 1) Create an election (owner)
  const now = Math.floor(Date.now() / 1000);
  const commitDeadline = now + 60;   // 1 min
  const revealDeadline = now + 120;  // 2 min
  const candidates = ["Alice", "Bob", "Charlie"];

  const electionAddress = await createFPTP("Board Election", commitDeadline, revealDeadline, candidates);

  // 2) Prepare three voters (you need their private keys funded with ETH if on a real network)
  // For demo: create random wallets (works best on a local dev chain)
  const voters = [ethers.Wallet.createRandom(), ethers.Wallet.createRandom(), ethers.Wallet.createRandom()]
    .map(w => w.connect(provider));

  console.log("Voters:", await Promise.all(voters.map(v => v.getAddress())));

  // 3) Each voter registers on the registry for THIS election
  for (const v of voters) {
    await registerVoterForElection(v, electionAddress);
  }

  // 4) Each voter commits (store their salts/secrets locally to reveal later)
  const commits = [];
  commits.push(await commitBallotFPTP(voters[0], electionAddress, 0, {})); // Alice
  commits.push(await commitBallotFPTP(voters[1], electionAddress, 1, {})); // Bob
  commits.push(await commitBallotFPTP(voters[2], electionAddress, 0, {})); // Alice

  // 5) Wait for reveal phase
  await waitUntilPhase(attach(electionAddress, fptpAbi, owner), "reveal");

  // 6) Reveal
  await revealBallot(voters[0], electionAddress, commits[0].ballotEncoded, commits[0].salt, commits[0].secret);
  await revealBallot(voters[1], electionAddress, commits[1].ballotEncoded, commits[1].salt, commits[1].secret);
  await revealBallot(voters[2], electionAddress, commits[2].ballotEncoded, commits[2].salt, commits[2].secret);

  // 7) Finalize (anyone can do it after revealDeadline)
  await waitUntilPhase(attach(electionAddress, fptpAbi, owner), "finalize");
  const tx = await attach(electionAddress, fptpAbi, owner).finalize();
  await tx.wait();

  // 8) Read winner (public state)
  const electionRead = attach(electionAddress, fptpAbi, owner);
  const winIdx = await electionRead.winner();
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