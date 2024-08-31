module game::GamingContract {
    use std::signer;
    use std::vector;
    use std::string;
    use std::error;
    use std::option::{Self, Option};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::aptos_account;
    use supra_addr::supra_vrf;

    const ENTRY_COIN: u64 = 100000000; // 1 Aptos
    const WINNER_ALREADY_SELECTED: u64 = 1;
    const LOTTERY_NOT_EXIST: u64 = 2;
    const COIN_AMOUNT_IS_NOT_ENOUGH_TO_PARTICIPATE: u64 = 3;
    const YOU_ARE_NOT_LOTTERY_OWNER: u64 = 4;
    const E_NO_PARTICIPANTS: u64 = 5;
    const E_ALREADY_PARTICIPATED: u64 = 6;

    const RESOURCE_SEED: vector<u8> = b"Lottery"; // This could be any seed

    struct Lottery has key {
        participants: vector<address>,
        winner: Option<address>,
        amount: u64,
        request_nonce: Option<u64>,
        random_number: Option<vector<u64>>,
        signer_cap: SignerCapability,
    }


    fun init_module(owner_signer: &signer) {
        let (resource_signer, signer_cap) = account::create_resource_account(owner_signer, RESOURCE_SEED);
        let lottery = Lottery {
            participants: vector::empty<address>(),
            winner: option::none(),
            amount: 0,
            request_nonce: option::none(),
            random_number: option::none(),
            signer_cap,
        };
        move_to(&resource_signer, lottery);
    }

    #[view]
    /// Get resource account address
    fun get_resource_address(): address {
        account::create_resource_address(&@game, RESOURCE_SEED)
    }

    /// this entry function is for player registration
    entry fun participate(user: &signer, amount: u64) acquires Lottery {
        let lottery_resource_address = get_resource_address();
        assert!(exists<Lottery>(lottery_resource_address), error::not_found(LOTTERY_NOT_EXIST));

        let lottery = borrow_global_mut<Lottery>(lottery_resource_address);
        assert!(option::is_none(&lottery.winner), error::invalid_state(WINNER_ALREADY_SELECTED));

        assert!(!vector::contains(&lottery.participants,  &signer::address_of(user)), error::already_exists(E_ALREADY_PARTICIPATED));

        // check amount should be more than entry fee
        assert!(amount > ENTRY_COIN, error::permission_denied(COIN_AMOUNT_IS_NOT_ENOUGH_TO_PARTICIPATE));
        aptos_account::transfer(user, lottery_resource_address, amount);

        vector::push_back(&mut lottery.participants, signer::address_of(user));
        lottery.amount = lottery.amount + amount;
    }

    /// generate random number
    public entry fun generate_random_number(owner_signer: &signer) acquires Lottery {
        let lottery_resource_address = get_resource_address();
        assert!(exists<Lottery>(lottery_resource_address), error::not_found(LOTTERY_NOT_EXIST));

        assert!(signer::address_of(owner_signer) == @game, error::unauthenticated(YOU_ARE_NOT_LOTTERY_OWNER));

        let lottery = borrow_global_mut<Lottery>(lottery_resource_address);
        assert!(!vector::is_empty(&lottery.participants), error::unavailable(E_NO_PARTICIPANTS));

        let callback_module = string::utf8(b"GamingContract");
        let callback_function = string::utf8(b"pick_winner"); // function name
        let rng_count: u8 = 1; // how many random number you want to generate
        let client_seed: u64 = 0; // client seed using as seed to generate random. if you don't want to use then just assign 0
        let num_confirmations: u64 = 1; // how many confirmation required for random number

        let nonce = supra_vrf::rng_request(owner_signer, @game, callback_module, callback_function,  rng_count, client_seed, num_confirmations);
        lottery.request_nonce = option::some(nonce);
    }

    /// supra vrf calls this function
    public entry fun pick_winner(
        nonce: u64,
        message: vector<u8>,
        signature: vector<u8>,
        caller_address: address,
        rng_count: u8,
        client_seed: u64,
    ) acquires Lottery {

        let lottery_resource_address = get_resource_address();
        assert!(exists<Lottery>(lottery_resource_address), error::not_found(LOTTERY_NOT_EXIST));

        let verified_num = supra_vrf::verify_callback(nonce, message, signature, caller_address, rng_count, client_seed);

        let lottery = borrow_global_mut<Lottery>(lottery_resource_address);
        lottery.random_number = option::some(verified_num);

        let random_number = *vector::borrow(&verified_num, 0);
        let random_index = random_number % vector::length(&lottery.participants);
        let winner_address = *vector::borrow(&lottery.participants, random_index);
        lottery.winner = option::some(winner_address);

        let resource_signer = account::create_signer_with_capability(&lottery.signer_cap);
        aptos_account::transfer(&resource_signer, winner_address, lottery.amount);
    }
}


