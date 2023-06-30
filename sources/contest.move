module contest::contest {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::event::emit;

    use std::option::{Self, Option};
    use std::vector;

    use capy::capy::{Self, Capy};


    /// Fee to participate to the contest
    const PARTICIPANT_FEE: u64 = 1000;
    /// Fee to support a participant 
    const SUPPORTER_FEE: u64 = 100;

    /// Error triggered upon attemting to operate over a contest that is not yet started
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
    /// Error triggered upon attempting to abandon a contest wihout authorization
    const EUnauthorizedWithdrawal: u64 = 6;

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

    /// The current winners
    struct Winners has store, copy, drop {
        /// The index of the first winner in the list of participants (see [`Contest`])
        first_place: u64,
        /// The index of the second winner in the list of participants (see [`Contest`])
        second_place: u64,
        /// The index of the third winner in the list of participants (see [`Contest`])
        third_place: u64
    }

    /// The main contest object
    struct Contest has key, store {
        id: UID,
        /// The edition of the contenst (monotonically increasing)
        edition: u64,
        /// The epoch number at which the contest starts (none if the contest did not yet start)
        start: Option<u64>,
        /// The prize for the winners (accumulated from the fees)
        prize: Balance<SUI>,
        /// The list of participants (never re-ordered, the index is used as fixed participant id)
        participants: vector<Option<Participant>>,
        /// The current winners of the contest (updated throughout the contest)
        winners: Winners
    }

    /// Get the participant at the given index; panics if the participant does not exist
    fun get_participant(participants: &vector<Option<Participant>>, particpant: u64): &Participant {
        option::borrow(vector::borrow(participants, particpant))
    }
    /// Get the participant at the given index (mutable); panics if the participant does not exist
    fun get_mut_participant(participants: &mut vector<Option<Participant>>, particpant: u64): &mut Participant {
        option::borrow_mut(vector::borrow_mut(participants, particpant))
    }

    /// A medal to grant to the winners of the contest
    struct Medal has key, store {
        id: UID,
        /// The winner's position (1 for the first prize, 2 for the second, etc)
        place: u64,
        /// The edition of the contest
        edition: u64,
        /// The prize (coins) won
        prize: u64,
        /// The number of supporters for the recipient of this medal
        supporters: u64,
        /// The id of the winner (irrevocably binding the medal to the winner)
        winner: ID,
    }

    /// Initialize an empty contest
    /// This method should be called only once (the contest object can be re-used)
    fun init(ctx: &mut TxContext) {
        let winners = Winners {
            first_place: 0,
            second_place: 0,
            third_place: 0
        };
        let contest = Contest {
            id: object::new(ctx),
            edition: 1,
            start: option::none(),
            prize: balance::zero(),
            participants: vector::empty(),
            winners
        };
        transfer::public_share_object(contest);
    }

    /// Start a new contest
    entry fun start(fee: &mut Coin<SUI>, contest: &mut Contest, capy: Capy, ctx: &mut TxContext) {
        participate(fee, contest, capy, ctx)
    }

    /// Enroll a capy into a contest
    entry fun participate(fee: &mut Coin<SUI>, contest: &mut Contest, capy: Capy, ctx: &mut TxContext) {
        // We only enroll participants during the epoch when the contest starts
        let current_epoch = tx_context::epoch(ctx);
        if (option::is_some(&contest.start)) {
            assert!(option::borrow(&contest.start) == &current_epoch, EParticipantEnrollementWindowClosed);
        } else {
            option::fill(&mut contest.start, current_epoch);

            // Emit a contest started event
            emit(ContestStarted{ edition: contest.edition });
        };
        
        // Pay the inscription fee (constitutes the price for the winner)
        let coin_balance = coin::balance_mut(fee);
        let paid = balance::split(coin_balance, PARTICIPANT_FEE);
        balance::join(&mut contest.prize, paid);

        // Create a new participant
        let participant = Participant {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            capy,
            score: 0,
            supporters: vector::empty()
        };
        let id = object::id(&participant);
        vector::push_back(&mut contest.participants, option::some(participant));

        // Emit a participant added event
        emit(ParticipantAdded{ id });
    }

    /// Support a participant
    entry fun support(fee: &mut Coin<SUI>, contest: &mut Contest, vote: u64, ctx: &mut TxContext) {
        // We only allow supporters at most one epoch after the start of the contest
        assert!(option::is_some(&contest.start), EContestNotStarted);
        let epoch = tx_context::epoch(ctx);
        let start = *option::borrow(&contest.start);
        assert!(epoch == start || epoch == start + 1, ESupporterEnrollementWindowClosed);
        // Ensure support is pledged to an existing participant
        assert!(vote < vector::length(&contest.participants), EInvalidVote);
        assert!(option::is_some(vector::borrow(&contest.participants, vote)), EParticipantNotFound);
        
        // Pay the support fee (constitutes the price for the winner)
        let coin_balance = coin::balance_mut(fee);
        let paid = balance::split(coin_balance, SUPPORTER_FEE);
        balance::join(&mut contest.prize, paid);

        // Update the participant with the new vote of support
        let supporter = tx_context::sender(ctx);
        let participant = get_mut_participant(&mut contest.participants, vote);
        participant.score = participant.score + 1;
        vector::push_back(&mut participant.supporters, supporter);  
        
        // Update the current winners of the contest
        let id = object::id(participant);
        let score = participant.score;
        let new_winners = update_winners(contest, vote, score);

        // Emit a participant supported event
        emit(ParticipantSupported{ 
            id,
            supporter,
            score,
            winners: new_winners
        })
    }

    /// Update the current winners of the contest
    fun update_winners(contest: &mut Contest, participant: u64, participant_score: u64): Winners {
        // Note that we only update the winners upon receiving a new vote of support, this means
        // all winners are guaranteed to exist (and not be none).
        let first_winner = get_participant(&contest.participants, contest.winners.first_place);
        let second_winner = get_participant(&contest.participants, contest.winners.second_place);
        let third_winner = get_participant(&contest.participants, contest.winners.third_place);

        if (participant_score > first_winner.score) {
            contest.winners.third_place = contest.winners.second_place;
            contest.winners.second_place = contest.winners.first_place;
            contest.winners.first_place = participant;
        } else if (participant_score > second_winner.score) {
            contest.winners.third_place = contest.winners.second_place;
            contest.winners.second_place = participant;
        } else if (participant_score > third_winner.score) {
            contest.winners.third_place = participant;
        };

        return contest.winners
    }
 
    /// Terminate the contest and distribute the prizes
    entry fun terminate(contest: &mut Contest, ctx: &mut TxContext) {
        // Ensure the contest can only be terminated after two epochs
        assert!(option::is_some(&contest.start), EContestNotStarted);
        assert!(tx_context::epoch(ctx) > *option::borrow(&contest.start) + 1, ECannotYetTerminateContest);
        
        // Distribute the prizes and medals to the winners
        distribute_prizes(contest, ctx);

        // Return all capies to their owner and delete the participant object
        while (!vector::is_empty(&contest.participants)) {
            let participant = vector::pop_back(&mut contest.participants);
            if (option::is_some(&participant)) {
                let Participant { 
                    id, 
                    owner, 
                    capy, 
                    score: _, 
                    supporters: _ 
                } = option::extract(&mut participant);

                transfer::public_transfer(capy, owner);
                object::delete(id);
            };
            option::destroy_none(participant);
        };

        // Emit a contest ended event
        emit(ContestEnded{ edition: contest.edition, winners: contest.winners });

        // Reset the contest object
        contest.edition = contest.edition + 1;
        contest.start = option::none();
        contest.winners = Winners {
            first_place: 0,
            second_place: 0,
            third_place: 0
        };
    }

    /// Distribute the prizes and medals to the winners
    fun distribute_prizes(contest: &mut Contest, ctx: &mut TxContext) {
        // Early return if there is no prize to pay
        let total_prize = balance::value(&contest.prize); 
        if (vector::is_empty(&contest.participants) || total_prize == 0) {
            return
        };

        // Transfer the prizes and medals to the winners
        let first_prize = total_prize / 2;
        let second_prize = total_prize / 4;
        let third_prize = total_prize / 8;

        grant_prize_and_medal(contest.winners.first_place, 1, first_prize, contest, ctx);
        grant_prize_and_medal(contest.winners.second_place, 2, second_prize, contest, ctx);
        grant_prize_and_medal(contest.winners.third_place, 3, third_prize, contest, ctx);

        // Transfer the remainder of the prize to the supporters of the first winner
        let remaining = total_prize - first_prize - second_prize - third_prize;
        if (remaining != 0) {
            pay_supporters(contest, remaining, ctx);
        };
    }

    /// Transfer a specific amount from the contest prize to the specified recipeint
    fun grant_prize_and_medal(recipient: u64, place: u64, prize: u64, contest: &mut Contest, ctx: &mut TxContext) {
        // Note that we only grant prixes to winners after ensuring the list of participants is not empty; this
        // means the winner is guaranteed to exist (and not be none).
        let particpant = get_mut_participant(&mut contest.participants, recipient);

        // Grant a medal to the capy
        let gold_medal = Medal {
            id: object::new(ctx),
            place,
            edition: contest.edition,
            prize,
            supporters: vector::length(&particpant.supporters),
            winner: object::id(&particpant.capy),
        };
        capy::add_item(&mut particpant.capy, gold_medal);

        // Transfer the prize to the owner of the capy
        let balance = balance::split(&mut contest.prize, prize);
        let coin = coin::from_balance(balance, ctx);
        transfer::public_transfer(coin, particpant.owner);
    }

    /// Divide the specified amount among the supporters of the first winner
    fun pay_supporters(contest: &mut Contest, remaining: u64, ctx: &mut TxContext) {
        let winner = option::borrow(vector::borrow_mut(&mut contest.participants, contest.winners.first_place));
        let number_of_supporters = vector::length(&winner.supporters);
        
        let i = 0;
        while (i < number_of_supporters) {
            let amount = remaining / number_of_supporters;
            if (amount == 0) {
                break
            };

            let supporter = vector::borrow(&winner.supporters, i);
            let balance = balance::split(&mut contest.prize, amount);
            let coin = coin::from_balance(balance, ctx);
            transfer::public_transfer(coin, *supporter);

            i = i + 1;
        }
    }

    /// Abandon the contest and immediatly retreive the capy
    entry fun withdraw(contest: &mut Contest, participant: u64, ctx: &mut TxContext) {
        // Ensure only the owner can withdraw the participant from the contest
        let participant = vector::borrow_mut(&mut contest.participants, participant);
        assert!(option::is_some(participant), EParticipantNotFound);
        assert!(option::borrow(participant).owner == tx_context::sender(ctx), EUnauthorizedWithdrawal);

        // Return the capy to the owner and delete the participant object
        let participant = option::extract(participant);
        let id = object::id(&participant);
        let Participant { 
            id: uid, 
            owner, 
            capy, 
            score: _, 
            supporters: _ 
        } = participant;

        transfer::public_transfer(capy, owner);
        object::delete(uid);

        // Emit a participant removed event
        emit(ParticipantRemoved{ id });
    }
}