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

/// Abandon the contest and immediatly retreive the capy
entry fun withdraw(contest: &mut Contest, participant: u64, ctx: &mut TxContext)
```

## License

This software is licensed as [Apache 2.0](LICENSE).
