module contest::contest {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::transfer;
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
    /// Error triggered upon attempting to terminate a contest before its end period
    const ECannotYetTerminateContest: u64 = 4;
    /// Error triggered upon attempting to abandon a contest wihout authorization
    const EUnauthorizedWithdrawal: u64 = 5;

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
    struct Winners has key, store {
        id: UID,
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
        participants: vector<Participant>,
        /// The current winners of the contest (updated throughout the contest)
        winners: Winners
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
            id: object::new(ctx),
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

    /// Enroll a capy to a contest
    entry fun participate(fee: &mut Coin<SUI>, contest: &mut Contest, capy: Capy, ctx: &mut TxContext) {
        // We only enroll participants during the epoch when the contest starts
        let current_epoch = tx_context::epoch(ctx);
        if (option::is_some(&contest.start)) {
            assert!(option::borrow(&contest.start) == &current_epoch, EParticipantEnrollementWindowClosed);
        } else {
            option::fill(&mut contest.start, current_epoch);
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
        vector::push_back(&mut contest.participants, participant);
    }

    /// Support a participant
    entry fun support(fee: &mut Coin<SUI>, contest: &mut Contest, vote: u64, ctx: &mut TxContext) {
        // Ensure support is pledged to an existing participant
        assert!(vote < vector::length(&contest.participants), EInvalidVote);
        // We only allow supporters at most one epoch after the start of the contest
        assert!(option::is_some(&contest.start), EContestNotStarted);
        let epoch = tx_context::epoch(ctx);
        let start = *option::borrow(&contest.start);
        assert!(epoch == start || epoch == start + 1, ESupporterEnrollementWindowClosed);
        
        // Pay the support fee (constitutes the price for the winner)
        let coin_balance = coin::balance_mut(fee);
        let paid = balance::split(coin_balance, SUPPORTER_FEE);
        balance::join(&mut contest.prize, paid);

        // Update the participant with the new vote of support
        let participant = vector::borrow_mut(&mut contest.participants, vote);
        participant.score = participant.score + 1;
        vector::push_back(&mut participant.supporters, tx_context::sender(ctx));        

        // Update the current winners of the contest
        update_winners(contest, vote, participant.score);
    }

    /// Update the current winners of the contest
    fun update_winners(contest: &mut Contest, participant: u64, participant_score: u64) {
        let first_winner = vector::borrow(&contest.participants, contest.winners.first_place);
        let second_winner = vector::borrow(&contest.participants, contest.winners.second_place);
        let third_winner = vector::borrow(&contest.participants, contest.winners.third_place);

        if (participant_score > first_winner.score) {
            contest.winners.third_place = contest.winners.second_place;
            contest.winners.second_place = contest.winners.first_place;
            contest.winners.first_place = participant;
        } else if (participant_score > second_winner.score) {
            contest.winners.third_place = contest.winners.second_place;
            contest.winners.second_place = participant;
        } else if (participant_score > third_winner.score) {
            contest.winners.third_place = participant;
        }
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
            let Participant { 
                id, 
                owner, 
                capy, 
                score: _, 
                supporters: _ 
            } = vector::pop_back(&mut contest.participants);

            transfer::public_transfer(capy, owner);
            object::delete(id);
        };

        // Reset the contest object
        contest.edition = contest.edition + 1;
        contest.start = option::none();

        contest.winners.first_place = 0;
        contest.winners.second_place = 0;
        contest.winners.third_place = 0;
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
        let contenstant = vector::borrow_mut(&mut contest.participants, recipient);

        // Grant a medal to the capy
        let gold_medal = Medal {
            id: object::new(ctx),
            place,
            edition: contest.edition,
            prize,
            supporters: vector::length(&contenstant.supporters),
            winner: object::id(&contenstant.capy),
        };
        capy::add_item(&mut contenstant.capy, gold_medal);

        // Transfer the prize to the owner of the capy
        let balance = balance::split(&mut contest.prize, prize);
        let coin = coin::from_balance(balance, ctx);
        transfer::public_transfer(coin, contenstant.owner);
    }

    /// Divide the specified amount among the supporters of the first winner
    fun pay_supporters(contest: &mut Contest, remaining: u64, ctx: &mut TxContext) {
        let winner = vector::borrow_mut(&mut contest.participants, contest.winners.first_place);
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
        let participant_object = vector::borrow(&contest.participants, participant);
        assert!(participant_object.owner == tx_context::sender(ctx), EUnauthorizedWithdrawal);

        // TODO: Withdraw without changing the index of the participants
        // A map would be nice be we cannot iterate over it 
        // It seems we need both a table and a vector of all keys of the table
        // Maybe make a generic iterable table?
        
        // Isolate all functions related to Winners into a separate module. That is almost all helpers
        // the winner module is aware of many structs of the contest module but never takes the contest
        // itself as parameter
    }
}