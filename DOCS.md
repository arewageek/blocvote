# BlocVote Contract — Reference Documentation

> **Network:** Ethereum Sepolia Testnet  
> **Solidity:** `^0.8.24`  
> **Toolchain:** Foundry (Forge + Cast)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Structures](#data-structures)
3. [Events](#events)
4. [Contract Functions](#contract-functions)
   - [Administration](#administration)
   - [Office Management](#office-management)
   - [Candidate Management](#candidate-management)
   - [Voting](#voting)
   - [Query](#query)
5. [Error Reference](#error-reference)
6. [REST API Endpoints](#rest-api-endpoints)
7. [Deployment (ContractFactory)](#deployment-contractfactory)

---

## Architecture Overview

```
ContractFactory
    └── deploy()  ──creates──▶  BlocVote (one per election)
                                    ├── chairman          (election authority)
                                    ├── offices[]         (e.g. President, Senator)
                                    ├── candidates[]      (contestants per office)
                                    ├── votes[]           (immutable archive)
                                    └── hasVoted[][]      (double-vote guard)
```

**Flow:**

```
1. Chairman registers offices
2. Chairman registers candidates per office
3. Voters authenticate off-chain → chairman submits batches via castVote()
4. Anyone reads results via getResult()
```

---

## Data Structures

### `Candidate`

| Field | Type | Description |
|---|---|---|
| `id` | `uint256` | Array index; auto-assigned on registration |
| `name` | `string` | Display name (non-empty) |
| `officeId` | `uint256` | ID of the office this candidate contests |
| `isValid` | `bool` | `true` = active; `false` = soft-deleted |
| `votes` | `uint256` | Accumulated vote count; persists across deactivation |

### `Office`

| Field | Type | Description |
|---|---|---|
| `id` | `uint256` | Array index; auto-assigned on registration |
| `name` | `string` | Display name (non-empty) |
| `isValid` | `bool` | `true` = active; `false` = soft-deleted |
| `candidatesCount` | `uint256` | Total candidates ever registered (never decrements) |

### `Vote` _(input to `castVote`)_

| Field | Type | Description |
|---|---|---|
| `candidateId` | `uint256` | Must match an existing, active candidate |
| `officeId` | `uint256` | Must match the candidate's registered office |
| `voterId` | `uint256` | Off-chain voter identifier (e.g. hashed NIN). Any non-zero `uint256` is valid |

### `Result` _(output of `getResult`)_

| Field | Type | Description |
|---|---|---|
| `candidateId` | `uint256` | Candidate's array index |
| `candidateName` | `string` | Candidate's display name |
| `officeId` | `uint256` | Office the candidate contests |
| `votes` | `uint256` | Current vote count |

---

## Events

All events are emitted on-chain and form the permanent audit trail.

| Event | Parameters | Emitted When |
|---|---|---|
| `ChairmanChanged` | `previousChairman`, `newChairman` | Constructor (from `address(0)`) or after `claimChairmanRole()` |
| `ChairmanProposed` | `chairman`, `pendingChairman` | `proposeChairman()` succeeds |
| `ChairmanProposalCancelled` | `chairman`, `cancelledProposal` | `cancelChairmanProposal()` succeeds |
| `OfficeRegistered` | `officeId`, `name` | `registerOffice()` succeeds |
| `OfficeStatusChanged` | `officeId`, `isValid` | `removeOffice()` or `reactivateOffice()` |
| `CandidateRegistered` | `candidateId`, `officeId`, `name` | `registerCandidate()` succeeds |
| `CandidateStatusChanged` | `candidateId`, `isValid` | `removeCandidate()` or `reactivateCandidate()` |
| `VoteCasted` | `voterId`, `officeId`, `candidateId` | Once per entry inside `castVote()` |

---

## Contract Functions

### Administration

> All admin functions require `msg.sender == chairman`.

---

#### `proposeChairman(address _newChairman)`

Initiates a two-step chairman handover.

**Input**

| Param | Type | Rules |
|---|---|---|
| `_newChairman` | `address` | Must not be `address(0)`. Must not be the current chairman. |

**Output:** none  
**Emits:** `ChairmanProposed(chairman, _newChairman)`

**Revert conditions**

| Message | Reason |
|---|---|
| `"unauthorized"` | Caller is not the current chairman |
| `"invalid chairman"` | `_newChairman` is `address(0)` |
| `"already chairman"` | `_newChairman` equals the current chairman |

---

#### `cancelChairmanProposal()`

Retracts an outstanding handover proposal before it is claimed.

**Input:** none  
**Output:** none  
**Emits:** `ChairmanProposalCancelled(chairman, cancelledAddress)`

**Revert conditions**

| Message | Reason |
|---|---|
| `"unauthorized"` | Caller is not the current chairman |
| `"no pending proposal"` | `pendingChairman` is already `address(0)` |

---

#### `claimChairmanRole()`

Step 2 of the handover — the pending chairman accepts and takes control.

**Input:** none (caller must be `pendingChairman`)  
**Output:** none  
**Emits:** `ChairmanChanged(previousChairman, newChairman)`

**Revert conditions**

| Message | Reason |
|---|---|
| `"unauthorized"` | Caller is not `pendingChairman` |

---

### Office Management

> All functions require `msg.sender == chairman`.

---

#### `registerOffice(string calldata _name)`

**Input**

| Param | Type | Rules |
|---|---|---|
| `_name` | `string` | Non-empty |

**Output:** none  
**Emits:** `OfficeRegistered(newOfficeId, _name)`  
**New office ID** = `offices.length` before push (auto-increments from 0).

| Revert | Reason |
|---|---|
| `"unauthorized"` | Not chairman |
| `"name required"` | Empty string |

---

#### `removeOffice(uint256 _officeId)`

Soft-deletes an office. Existing candidates are not deleted but cannot receive votes while the office is inactive.

**Input**

| Param | Type | Rules |
|---|---|---|
| `_officeId` | `uint256` | Must exist and currently be `isValid = true` |

**Output:** none  
**Emits:** `OfficeStatusChanged(_officeId, false)`

| Revert | Reason |
|---|---|
| `"unauthorized"` | Not chairman |
| `"invalid office id"` | ID ≥ `offices.length` |
| `"already removed"` | Office already inactive |

---

#### `reactivateOffice(uint256 _officeId)`

Re-enables a previously removed office.

**Input**

| Param | Type | Rules |
|---|---|---|
| `_officeId` | `uint256` | Must exist and currently be `isValid = false` |

**Output:** none  
**Emits:** `OfficeStatusChanged(_officeId, true)`

| Revert | Reason |
|---|---|
| `"unauthorized"` | Not chairman |
| `"invalid office id"` | ID ≥ `offices.length` |
| `"already active"` | Office already active |

---

### Candidate Management

> All functions require `msg.sender == chairman`.

---

#### `registerCandidate(string calldata _name, uint256 _officeId)`

**Input**

| Param | Type | Rules |
|---|---|---|
| `_name` | `string` | Non-empty |
| `_officeId` | `uint256` | Must exist and currently be `isValid = true` |

**Output:** none  
**Emits:** `CandidateRegistered(newCandidateId, _officeId, _name)`  
Also increments `offices[_officeId].candidatesCount`.

| Revert | Reason |
|---|---|
| `"unauthorized"` | Not chairman |
| `"name required"` | Empty string |
| `"invalid office id"` | ID ≥ `offices.length` |
| `"Office invalid"` | Office is soft-deleted |

---

#### `removeCandidate(uint256 _candidateId)`

Soft-deletes a candidate. Their accumulated votes are preserved in storage.

**Input**

| Param | Type | Rules |
|---|---|---|
| `_candidateId` | `uint256` | Must exist and currently be `isValid = true` |

**Output:** none  
**Emits:** `CandidateStatusChanged(_candidateId, false)`

| Revert | Reason |
|---|---|
| `"unauthorized"` | Not chairman |
| `"invalid candidate id"` | ID ≥ `candidates.length` |
| `"already removed"` | Candidate already inactive |

---

#### `reactivateCandidate(uint256 _candidateId)`

Re-enables a previously removed candidate. Their historical vote count is restored into `getResult()`.

**Input**

| Param | Type | Rules |
|---|---|---|
| `_candidateId` | `uint256` | Must exist and currently be `isValid = false` |

**Output:** none  
**Emits:** `CandidateStatusChanged(_candidateId, true)`

| Revert | Reason |
|---|---|
| `"unauthorized"` | Not chairman |
| `"invalid candidate id"` | ID ≥ `candidates.length` |
| `"already active"` | Candidate already active |

---

### Voting

> Requires `msg.sender == chairman`.

---

#### `castVote(Vote[] memory _votes)`

Submits a batch of votes atomically. If **any single entry fails validation**, the **entire transaction reverts** — no partial state is written.

**Input**

```solidity
// Example: voter 12345 votes for candidate 0 (President) and candidate 2 (Senator)
[
  { candidateId: 0, officeId: 0, voterId: 12345 },
  { candidateId: 2, officeId: 1, voterId: 12345 }
]
```

| Field | Rules |
|---|---|
| `candidateId` | Must be < `candidates.length` and `isValid = true` |
| `officeId` | Must be < `offices.length`, `isValid = true`, and match `candidates[candidateId].officeId` |
| `voterId` | `hasVoted[voterId][officeId]` must be `false`. Any `uint256` including `0` is a valid ID. |

**Output:** none  
**Emits:** one `VoteCasted(voterId, officeId, candidateId)` per entry  
**Side effects:** `hasVoted[voterId][officeId] = true`, `candidates[candidateId].votes++`, entry appended to `votes[]`

| Revert | Reason |
|---|---|
| `"unauthorized"` | Not chairman |
| `"empty ballot"` | Array length is 0 |
| `"invalid candidate id"` | `candidateId` ≥ `candidates.length` |
| `"invalid office id"` | `officeId` ≥ `offices.length` |
| `"Candidate invalid"` | Candidate is soft-deleted |
| `"Office invalid"` | Office is soft-deleted |
| `"candidate does not contest this office"` | `officeId` doesn't match candidate's registered office |
| `"already voted"` | `hasVoted[voterId][officeId]` is already `true` |

---

### Query

> Anyone may call these. No gas cost (view functions).

---

#### `getResult() → Result[]`

Returns one entry for every **currently active** candidate.

**Input:** none

**Output**

```json
[
  { "candidateId": 0, "candidateName": "Alice", "officeId": 0, "votes": 3 },
  { "candidateId": 2, "candidateName": "Carol", "officeId": 1, "votes": 2 }
]
```

> Removed candidates are excluded. Their votes are not counted until reactivated.

---

#### `candidateResult(uint256 _candidateId) → uint256`

Returns the raw vote count for one candidate (active or removed).

| Revert | Reason |
|---|---|
| `"invalid candidate id"` | ID ≥ `candidates.length` |

---

#### `candidatesCount() → uint256`

Total candidates ever registered. Does **not** decrease on removal.

#### `officesCount() → uint256`

Total offices ever registered. Does **not** decrease on removal.

#### `votesCount() → uint256`

Total individual votes recorded in the archive.

#### `hasVoted(uint256 voterId, uint256 officeId) → bool`

Check whether a specific voter has already voted for a specific office.

#### `chairman() → address`

Current election authority.

#### `pendingChairman() → address`

Proposed successor. Returns `address(0)` when no handover is in progress.

#### `deployer() → address`

The account that deployed this contract (immutable). When deployed via `ContractFactory`, this is the factory's address, not the human operator.

---

## Error Reference

Complete list of all revert messages in the contract.

| Message | Functions |
|---|---|
| `"unauthorized"` | `proposeChairman`, `cancelChairmanProposal`, `castVote`, all management functions |
| `"invalid chairman"` | `constructor`, `proposeChairman` |
| `"already chairman"` | `proposeChairman` |
| `"no pending proposal"` | `cancelChairmanProposal` |
| `"name required"` | `registerOffice`, `registerCandidate` |
| `"invalid office id"` | `registerCandidate`, `removeOffice`, `reactivateOffice`, `castVote` |
| `"Office invalid"` | `registerCandidate`, `castVote` |
| `"already removed"` | `removeCandidate`, `removeOffice` |
| `"already active"` | `reactivateCandidate`, `reactivateOffice` |
| `"invalid candidate id"` | `removeCandidate`, `reactivateCandidate`, `candidateResult`, `castVote` |
| `"Candidate invalid"` | `castVote` |
| `"candidate does not contest this office"` | `castVote` |
| `"already voted"` | `castVote` |
| `"empty ballot"` | `castVote` |

---

## REST API Endpoints

Base URL: `http://localhost:4000` (configurable via `PORT` env var)

### Read

| Method | Endpoint | Response |
|---|---|---|
| `GET` | `/chairman` | `{ "chairman": "0x..." }` |
| `GET` | `/office/:id` | `{ "office": "President" }` |
| `GET` | `/candidate/:id` | `{ "office": { "name": "Alice", "officeId": 0, "votes": 3 } }` |
| `GET` | `/votes/:index` | `{ "candidateId": 0, "officeId": 0, "voterId": 12345 }` |
| `GET` | `/result` | `{ "result": [ Result[] ] }` |

### Write

| Method | Endpoint | Body / Params | Response |
|---|---|---|---|
| `GET` | `/office/new/:office` | URL param: office name | `{ "registered": { ...receipt } }` |
| `GET` | `/candidate/new/:name/:office` | URL params: name, officeId | `{ "registered": { ...receipt } }` |
| `POST` | `/vote/:voter/:candidate` | URL params: voterId (number), candidate letter `A–K` | `{ "votehash": "0x..." }` |
| `GET` | `/vote` | JSON body (see below) | `{ "voter_ids": [...], "votes": [...] }` |

#### Batch vote body (`GET /vote`)

```json
{
  "votes":     ["A", "C"],
  "voter_ids": [12345, 12345]
}
```

> Letters map to candidate IDs: `A=0, B=1, C=2, D=3, ...`  
> The API looks up each candidate's `officeId` on-chain automatically before submitting.

### Telegram Integration

Both vote endpoints (`POST /vote/:voter/:candidate` and `GET /vote`) send a Telegram
notification to configured recipients after a successful transaction, containing:
- The transaction hash
- A link to view the tx on Sepolia Etherscan
- A link to view the contract on Etherscan

---

## Deployment (ContractFactory)

```solidity
ContractFactory.deploy() → address
```

Deploys a new independent `BlocVote` instance with `msg.sender` as chairman.

| Function | Returns | Description |
|---|---|---|
| `deploy()` | `address` | Deploys BlocVote; caller becomes chairman |
| `deployedCount()` | `uint256` | Number of instances deployed via this factory |
| `blocvoteContracts(index)` | `address` | Address of the Nth deployed instance |

**Event:** `BlocVoteDeployed(address indexed chairman, address indexed blocVote)`
