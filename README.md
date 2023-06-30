> **Note to readers:** This smart contract is a test to play with the functionalities of Sui move. It has not been tested and it would be unwise to deploy it on mainnet.

# Capy Contest

[![license](https://img.shields.io/badge/license-Apache-blue.svg?style=flat-square)](LICENSE)

Simple smart contract implementing contest for [Capys](https://suifrens.com). Users enroll their Capy into the contest by locking them into the smart contract and paying a fee. Any user can then vote for their favorite Capy by paying a small fee. At the end of the contest, the three Capys with the most votes win; they receive a unique medal (bound to the Capy and the contest's edition) and their owners receive a price composed of all the fees collected into the smart contract. Each contest runs for at least 2 epochs and can then be reset to start over.

## Contract API

The smart contract exposes the following entry functions.

```move
/// Enroll a capy into a contest
entry fun participate(fee: &mut Coin<SUI>, contest: &mut Contest, capy: Capy, ctx: &mut TxContext)

/// Support a participant
entry fun support(fee: &mut Coin<SUI>, contest: &mut Contest, vote: u64, ctx: &mut TxContext)

/// Terminate the contest and distribute the prizes
entry fun terminate(contest: &mut Contest, ctx: &mut TxContext)

/// Abandon the contest and immediately retrieve the capy
entry fun withdraw(contest: &mut Contest, participant: u64, ctx: &mut TxContext)
```

## Errors

These functions may return the following error codes.

```move
/// Error triggered upon attempting to operate over a contest that is not yet started
const EContestNotStarted: u64 = 0;

/// Error triggered upon attempting to enroll a participant after the allowed period
const EParticipantEnrollementWindowClosed: u64 = 1;

/// Error triggered upon attempting to support a participant after the allowed period
const ESupporterEnrollementWindowClosed: u64 = 2;

/// Error triggered upon attempting to support an unknown participant
const EInvalidVote: u64 = 3;

/// Error triggered upon attempting to access an unknown participant
const EParticipantNotFound: u64 = 4;

/// Error triggered upon attempting to terminate a contest before its end period
const ECannotYetTerminateContest: u64 = 5;

/// Error triggered upon attempting to abandon a contest without authorization
const EUnauthorizedWithdrawal: u64 = 6;
```

## Events

The smart contract emits the following events.

```move
/// Event emitted when a contest starts
struct ContestStarted has copy, drop {
    edition: u64,
}

/// Event emitted when a contest ends
struct ContestEnded has copy, drop {
    edition: u64,
    winners: Winners
}

/// Event emitted when a new participant is added to the contest
struct ParticipantAdded has copy, drop {
    id: ID,
}

/// Event emitted when a participant is removed from the contest
struct ParticipantRemoved has copy, drop {
    id: ID,
}

/// Event emitted when a participant is supported
struct ParticipantSupported has copy, drop {
    id: ID,
    supporter: address,
    score: u64,
    winners: Winners
}

/// A contest participant
struct Participant has key, store {
    id: UID,
    /// The address owning the capy
    owner: address,
    /// The competing capy
    capy: Capy,
    /// The total score accumulated from supporters
    score: u64,
    /// The list of supporters
    supporters: vector<address>
}
```

## License

This software is licensed as [Apache 2.0](LICENSE).
