
import { ethers } from "ethers";
import fs from "fs";

// ==== CONFIG ====
const RPC_URL = "https://sepolia.infura.io";   // your provider
const PRIVATE_KEY = "";                        // deployer/admin key
const factoryAddress = "0x1885e87c6b4bc0916306cc7a2f9ec8ff63eede3d";                     // deployed ElectionFactory

// Load ABIs
const factoryAbi = JSON.parse(
  fs.readFileSync("./artifacts/ElectionFactory.json")
).abi;
const fptpAbi = JSON.parse(fs.readFileSync("./artifacts/FPTPElection.json")).abi;
const irvAbi = JSON.parse(fs.readFileSync("./artifacts/IRVElection.json")).abi;
const bordaAbi = JSON.parse(fs.readFileSync("./artifacts/BordaElection.json")).abi;
const condorcetAbi = JSON.parse(fs.readFileSync("./artifacts/CondorcetElection.json")).abi;
const prAbi = JSON.parse(fs.readFileSync("./artifacts/PRElectionDhondt.json")).abi;

// ==== PROVIDER + SIGNER ====
const provider = new ethers.JsonRpcProvider(RPC_URL);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

// ================== HELPERS ==================
async function deployElection(factory, type, name, candidatesOrParties, seats, thresholdBps) {
  const now = Math.floor(Date.now() / 1000);
  const commitDeadline = now + 60; // 1 min commit
  const revealDeadline = now + 120; // 2 min reveal

  let tx;
  if (type === "FPTP") {
    tx = await factory.createFPTP(name, commitDeadline, revealDeadline, candidatesOrParties);
  } else if (type === "IRV") {
    tx = await factory.createIRV(name, commitDeadline, revealDeadline, candidatesOrParties);
  } else if (type === "BORDA") {
    tx = await factory.createBorda(name, commitDeadline, revealDeadline, candidatesOrParties);
  } else if (type === "CONDORCET") {
    tx = await factory.createCondorcet(name, commitDeadline, revealDeadline, candidatesOrParties);
  } else if (type === "PR") {
    tx = await factory.createPRDhondt(
      name,
      commitDeadline,
      revealDeadline,
      candidatesOrParties,
      seats,
      thresholdBps
    );
  } else {
    throw new Error("Unknown election type!");
  }

  const receipt = await tx.wait();
  const event = receipt.logs
    .map(l => {
      try {
        return factory.interface.parseLog(l);
      } catch {
        return null;
      }
    })
    .filter(e => e && e.name.toUpperCase().includes(type))[0];

  return event.args.election;
}

async function registerVoters(election, abi, voterWallets) {
  const contract = new ethers.Contract(election, abi, signer);

  for (let v of voterWallets) {
    const tx = await contract.registerVoter(v.address);
    await tx.wait();
    console.log("Registered voter:", v.address);
  }
}

async function commitVotes(election, abi, votes, salts) {
  const contract = new ethers.Contract(election, abi, signer);

  const commits = votes.map((v, i) =>
    ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "string"], [v, salts[i]])
    )
  );

  for (let i = 0; i < votes.length; i++) {
    const tx = await contract.commitVote(commits[i]);
    await tx.wait();
    console.log(`Voter ${i + 1} committed`);
  }
}

async function revealVotes(election, abi, votes, salts) {
  const contract = new ethers.Contract(election, abi, signer);

  for (let i = 0; i < votes.length; i++) {
    const tx = await contract.revealVote(votes[i], salts[i]);
    await tx.wait();
    console.log(`Voter ${i + 1} revealed`);
  }
}

async function getWinner(election, abi) {
  const contract = new ethers.Contract(election, abi, signer);
  const winner = await contract.getWinner();
  console.log("🏆 Election Winner is:", winner.toString());
}

// ================== MAIN ==================
async function main() {
  const factory = new ethers.Contract(factoryAddress, factoryAbi, signer);

  // Example: Create & run a FPTP election
  const electionAddr = await deployElection(
    factory,
    "FPTP",
    "Board Election",
    ["Alice", "Bob", "Charlie"]
  );
  console.log("Election deployed at:", electionAddr);

  const voterWallets = [
    ethers.Wallet.createRandom(),
    ethers.Wallet.createRandom(),
    ethers.Wallet.createRandom()
  ];

  await registerVoters(electionAddr, fptpAbi, voterWallets);

  const votes = [0, 1, 0];
  const salts = ["s1", "s2", "s3"];

  await commitVotes(electionAddr, fptpAbi, votes, salts);

  console.log("⏳ Waiting until reveal...");
  await new Promise(r => setTimeout(r, 60000)); // wait commit phase

  await revealVotes(electionAddr, fptpAbi, votes, salts);

  await getWinner(electionAddr, fptpAbi);

  // You can repeat the same for IRV, BORDA, CONDORCET, PR by swapping type & ABI
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

