# 📡 Secure Messaging Protocol - Connection Management

A decentralized messaging protocol built with Clarity for the Stacks blockchain. This smart contract allows registered participants to establish secure connections, exchange encrypted communications, and manage cryptographic identities in a trustless environment.

---

## 🚀 Features

* **Participant Registration & Identity Management**
  Users register with a cryptographic public key and maintain a profile including inbound/outbound message counters and last interaction time.

* **Encrypted Messaging System**
  Supports sending encrypted messages categorized by type (e.g., `"normal"`, `"private"`), with configurable expiration durations.

* **Connection Management**
  Only authorized connections can exchange messages. Participants can create and remove connections dynamically.

* **Pending Communication Tracking**
  Pending messages are tracked and can be confirmed upon receipt.

* **Governance Mechanism**
  Protocol governor can initialize and transfer control securely.

---

## 📦 Contract Components

### Constants

Defines various status codes and system limits:

* `CONTENT-SIZE-LIMIT` – Max size for encrypted message content.
* `CRYPTO-KEY-LENGTH` – Required length for cryptographic keys.
* `CONNECTION-LIMIT` – Max number of connections per participant.
* `DEFAULT-EXPIRATION-PERIOD` – Default message expiration in blocks.

### Data Maps

* `participant-registry` – Stores participant metadata.
* `communication-store` – Stores encrypted messages with metadata.
* `participant-pending-items` – Lists pending message IDs per participant.
* `participant-network` – Lists authorized connections per participant.

---

## 📚 Public Functions

### 👤 Participant Management

* `register-participant`
  Registers a participant with a cryptographic key.

* `update-crypto-key`
  Updates the participant’s cryptographic key.

### ✉️ Communications

* `transmit-secure-content`
  Sends encrypted content to a connected participant.

* `confirm-receipt`
  Confirms a received communication and updates status.

### 🤝 Connection Management

* `create-connection`
  Establishes a new authorized connection between participants.

* `remove-connection`
  Removes an existing connection.

### 🛠 Governance

* `initialize-protocol`
  Protocol initializer (must be called by governor).

* `transfer-governance`
  Transfers protocol governance to a new address.

---

## 🔍 Read-Only Functions

* `fetch-participant-data`
  Gets the full profile of a participant.

* `is-participant-verified`
  Checks if a participant is registered.

* `fetch-communication`
  Fetches a message by ID.

* `fetch-protocol-metrics`
  Returns total communications and active participants.

* `fetch-participant-pending`
  Lists pending messages for a participant.

* `fetch-participant-connections`
  Gets the list of authorized connections for a participant.

* `is-valid-connection`
  Verifies if a connection exists.

* `is-communication-valid`
  Checks whether a message has expired.

---

## 🧪 Example Usage

### Register a Participant

```clarity
(register-participant 0x03abcdef...33bytes)
```

### Create a Connection

```clarity
(create-connection 'ST2...xyz)
```

### Send a Message

```clarity
(transmit-secure-content 
  'ST2...abc 
  0xencryptedPayload 
  "private" 
  u200)
```

---

## ⚠️ Error Codes

| Code | Meaning                     |
| ---- | --------------------------- |
| 200  | Participant unregistered    |
| 201  | Participant already exists  |
| 202  | Access denied               |
| 203  | Communication not found     |
| 204  | Content size limit exceeded |
| 205  | Invalid crypto key          |
| 206  | Process failure             |
| 207  | Connection not found        |
| 208  | Connection already exists   |
| 209  | Self-connection prohibited  |
| 210  | Communication expired       |

---

## 🔐 Security & Design Considerations

* All message content is assumed encrypted client-side before transmission.
* Connection model ensures private and permissioned communication.
* Expiry blocks enforce message lifecycle limits.
* Pending communications must be confirmed explicitly to ensure delivery guarantees.
