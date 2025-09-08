/// Villa RWA Dynamic NFT Implementation for Sui
/// Final working implementation without villa status (handled off-chain)
module villa_rwa::villa_dnft {
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use std::string::{Self, String};
    use std::vector;

    // ===== Error Codes =====
    const ENotAuthorized: u64 = 1;
    const EInvalidMaxShares: u64 = 11;
    const EInvalidPrice: u64 = 12;
    const EListingNotFound: u64 = 14;
    const EListingExpired: u64 = 15;
    const EExceedsProjectLimit: u64 = 9;
    const EExceedsVillaLimit: u64 = 10;
    const EInvalidCommissionRate: u64 = 16;

    // ===== Capability Objects =====
    struct VILLA_DNFT has drop {}

    struct AppCap has key, store {
        id: UID,
        app_address: address,
    }

    struct AdminCap has key, store {
        id: UID,
        app_address: address,
    }

    struct AssetManagerCap has key, store {
        id: UID,
        app_address: address,
    }

    // ===== Main Data Structures =====

    struct VillaProject has key, store {
        id: UID,
        project_id: String,
        name: String,
        description: String,
        total_villas: u64,
        max_total_shares: u64, // 400,000 for entire project
        total_shares_issued: u64,
        commission_rate: u64, // Basis points (e.g., 250 = 2.5%)
        affiliate_rate: u64, // Basis points (e.g., 100 = 1%)
        created_at: u64,
        updated_at: u64,
    }

    struct VillaMetadata has key, store {
        id: UID,
        project_id: String,
        villa_id: String,
        name: String,
        description: String,
        image_url: String, // Walrus storage URL
        location: String,
        max_shares: u64, // Max shares for this villa
        shares_issued: u64,
        price_per_share: u64,
        created_at: u64,
        updated_at: u64,
    }

    struct VillaShareNFT has key, store {
        id: UID,
        project_id: String,
        villa_id: String,
        owner: address,
        affiliate_code: String,
        is_affiliate_active: bool,
        created_at: u64,
    }

    struct DNFTListing has key, store {
        id: UID,
        share_nft_id: ID,
        project_id: String,
        villa_id: String,
        seller: address,
        price: u64,
        affiliate_code: String,
        is_active: bool,
        created_at: u64,
        expires_at: u64,
    }

    struct DNFTTrade has key, store {
        id: UID,
        share_nft_id: ID,
        project_id: String,
        villa_id: String,
        seller: address,
        buyer: address,
        price: u64,
        affiliate_commission: u64,
        app_commission: u64,
        timestamp: u64,
    }

    // Commission data that can be dropped
    struct SaleCommission has drop {
        affiliate_commission: u64,
        app_commission: u64,
        total_price: u64,
    }

    struct VillaMarketplace has key, store {
        id: UID,
        project_id: String,
        listings: Table<ID, DNFTListing>,
        trades: Table<ID, DNFTTrade>,
        commission_rate: u64,
        affiliate_rate: u64,
        created_at: u64,
    }

    struct AffiliateReward has key, store {
        id: UID,
        affiliate_code: String,
        owner: address,
        total_earned: u64,
        total_paid: u64,
        pending_amount: u64,
        created_at: u64,
        updated_at: u64,
    }

    struct AppTreasury has key, store {
        id: UID,
        project_id: String,
        total_earned: u64,
        total_paid: u64,
        pending_amount: u64,
        created_at: u64,
        updated_at: u64,
    }

    // ===== Events =====

    struct VillaProjectCreated has copy, drop {
        project_id: String,
        name: String,
        max_total_shares: u64,
        created_at: u64,
    }

    struct VillaMetadataCreated has copy, drop {
        project_id: String,
        villa_id: String,
        name: String,
        max_shares: u64,
        created_at: u64,
    }

    struct VillaSharesMinted has copy, drop {
        project_id: String,
        villa_id: String,
        amount: u64,
        total_shares_issued: u64,
        created_at: u64,
    }

    struct DNFTListed has copy, drop {
        share_nft_id: ID,
        seller: address,
        price: u64,
        created_at: u64,
    }

    struct DNFTBought has copy, drop {
        share_nft_id: ID,
        buyer: address,
        seller: address,
        price: u64,
        affiliate_commission: u64,
        app_commission: u64,
    }

    struct AffiliateRewardEarned has copy, drop {
        affiliate_code: String,
        owner: address,
        amount: u64,
        timestamp: u64,
    }

    struct CommissionPaid has copy, drop {
        recipient: address,
        amount: u64,
        timestamp: u64,
    }

    // ===== Initialization =====

    fun init(_witness: VILLA_DNFT, ctx: &mut TxContext) {
        // Create app capability
        let app_cap = AppCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        transfer::share_object(app_cap);

        // Create admin capability
        let admin_cap = AdminCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        transfer::share_object(admin_cap);

        // Create asset manager capability
        let asset_manager_cap = AssetManagerCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        transfer::share_object(asset_manager_cap);
    }

    // ===== Project Management =====

    public fun create_villa_project(
        _app_cap: &AppCap,
        project_id: String,
        name: String,
        description: String,
        max_total_shares: u64,
        commission_rate: u64,
        affiliate_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaProject {
        assert!(max_total_shares > 0, EInvalidMaxShares);
        assert!(commission_rate <= 10000, EInvalidCommissionRate);
        assert!(affiliate_rate <= 10000, EInvalidCommissionRate);

        let project = VillaProject {
            id: object::new(ctx),
            project_id,
            name,
            description,
            total_villas: 0,
            max_total_shares,
            total_shares_issued: 0,
            commission_rate,
            affiliate_rate,
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        };

        event::emit(VillaProjectCreated {
            project_id: project.project_id,
            name: project.name,
            max_total_shares: project.max_total_shares,
            created_at: project.created_at,
        });

        project
    }

    public fun create_villa_metadata(
        _app_cap: &AppCap,
        project: &mut VillaProject,
        villa_id: String,
        name: String,
        description: String,
        image_url: String,
        location: String,
        max_shares: u64,
        price_per_share: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaMetadata {
        assert!(max_shares > 0, EInvalidMaxShares);
        assert!(price_per_share > 0, EInvalidPrice);
        assert!(project.total_shares_issued + max_shares <= project.max_total_shares, EExceedsProjectLimit);

        let villa_metadata = VillaMetadata {
            id: object::new(ctx),
            project_id: project.project_id,
            villa_id,
            name,
            description,
            image_url,
            location,
            max_shares,
            shares_issued: 0,
            price_per_share,
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        };

        project.total_villas = project.total_villas + 1;
        project.updated_at = clock::timestamp_ms(clock);

        event::emit(VillaMetadataCreated {
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            name: villa_metadata.name,
            max_shares: villa_metadata.max_shares,
            created_at: villa_metadata.created_at,
        });

        villa_metadata
    }

    // ===== Minting Functions =====

    public fun mint_villa_share(
        _app_cap: &AppCap,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        assert!(villa_metadata.shares_issued < villa_metadata.max_shares, EExceedsVillaLimit);
        assert!(project.total_shares_issued < project.max_total_shares, EExceedsProjectLimit);

        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            owner: tx_context::sender(ctx),
            affiliate_code: generate_affiliate_code(tx_context::sender(ctx), clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
        };

        villa_metadata.shares_issued = villa_metadata.shares_issued + 1;
        villa_metadata.updated_at = clock::timestamp_ms(clock);
        project.total_shares_issued = project.total_shares_issued + 1;
        project.updated_at = clock::timestamp_ms(clock);

        event::emit(VillaSharesMinted {
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            amount: 1,
            total_shares_issued: villa_metadata.shares_issued,
            created_at: clock::timestamp_ms(clock),
        });

        share_nft
    }

    public fun mint_villa_shares_batch(
        _app_cap: &AppCap,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): vector<VillaShareNFT> {
        assert!(amount > 0, EInvalidMaxShares);
        assert!(villa_metadata.shares_issued + amount <= villa_metadata.max_shares, EExceedsVillaLimit);
        assert!(project.total_shares_issued + amount <= project.max_total_shares, EExceedsProjectLimit);

        let shares = vector::empty<VillaShareNFT>();

        let i = 0;
        while (i < amount) {
            let share_nft = VillaShareNFT {
                id: object::new(ctx),
                project_id: project.project_id,
                villa_id: villa_metadata.villa_id,
                owner: tx_context::sender(ctx),
                affiliate_code: generate_affiliate_code(tx_context::sender(ctx), clock, ctx),
                is_affiliate_active: true,
                created_at: clock::timestamp_ms(clock),
            };
            vector::push_back(&mut shares, share_nft);
            i = i + 1;
        };

        villa_metadata.shares_issued = villa_metadata.shares_issued + amount;
        villa_metadata.updated_at = clock::timestamp_ms(clock);
        project.total_shares_issued = project.total_shares_issued + amount;
        project.updated_at = clock::timestamp_ms(clock);

        event::emit(VillaSharesMinted {
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            amount,
            total_shares_issued: villa_metadata.shares_issued,
            created_at: clock::timestamp_ms(clock),
        });

        shares
    }

    // ===== Marketplace Functions =====

    public fun create_marketplace(
        _app_cap: &AppCap,
        project_id: String,
        commission_rate: u64,
        affiliate_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaMarketplace {
        VillaMarketplace {
            id: object::new(ctx),
            project_id,
            listings: table::new(ctx),
            trades: table::new(ctx),
            commission_rate,
            affiliate_rate,
            created_at: clock::timestamp_ms(clock),
        }
    }

    // FIXED: Properly consume share_nft by extracting data and using ID before deleting UID
    public fun list_dnft_for_sale(
        marketplace: &mut VillaMarketplace,
        share_nft: VillaShareNFT,
        price: u64,
        expires_at: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(price > 0, EInvalidPrice);
        assert!(expires_at > clock::timestamp_ms(clock), EListingExpired);

        // Extract data from share_nft (this consumes the share_nft)
        let VillaShareNFT {
            id: share_nft_id,
            project_id,
            villa_id,
            owner: seller,
            affiliate_code,
            is_affiliate_active: _,
            created_at: _,
        } = share_nft;

        // Get the ID before deleting the UID
        let share_nft_id_value = object::uid_to_inner(&share_nft_id);

        let listing = DNFTListing {
            id: object::new(ctx),
            share_nft_id: share_nft_id_value,
            project_id,
            villa_id,
            seller,
            price,
            affiliate_code,
            is_active: true,
            created_at: clock::timestamp_ms(clock),
            expires_at,
        };

        table::add(&mut marketplace.listings, listing.share_nft_id, listing);

        // Delete the UID after using it
        object::delete(share_nft_id);

        event::emit(DNFTListed {
            share_nft_id: share_nft_id_value,
            seller,
            price,
            created_at: clock::timestamp_ms(clock),
        });
    }

    // FIXED: Properly handle listing consumption and create new share_nft
    public fun buy_dnft_from_marketplace(
        marketplace: &mut VillaMarketplace,
        listing_id: ID,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (VillaShareNFT, SaleCommission) {
        let listing = table::remove(&mut marketplace.listings, listing_id);
        
        assert!(listing.is_active, EListingNotFound);
        assert!(clock::timestamp_ms(clock) <= listing.expires_at, EListingExpired);
        
        // Extract data from listing (this consumes the listing)
        let DNFTListing {
            id: listing_id_uid,
            share_nft_id,
            project_id,
            villa_id,
            seller,
            price: total_price,
            affiliate_code: _,
            is_active: _,
            created_at: _,
            expires_at: _,
        } = listing;
        
        let affiliate_commission = (total_price * marketplace.affiliate_rate) / 10000;
        let app_commission = (total_price * marketplace.commission_rate) / 10000;
        
        let commission = SaleCommission {
            affiliate_commission,
            app_commission,
            total_price,
        };
        
        // Transfer payment to seller
        transfer::public_transfer(payment, seller);
        
        // Create new share_nft for buyer
        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id,
            villa_id,
            owner: tx_context::sender(ctx),
            affiliate_code: generate_affiliate_code(tx_context::sender(ctx), clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
        };
        
        // Record trade
        let trade = DNFTTrade {
            id: object::new(ctx),
            share_nft_id,
            project_id,
            villa_id,
            seller,
            buyer: tx_context::sender(ctx),
            price: total_price,
            affiliate_commission,
            app_commission,
            timestamp: clock::timestamp_ms(clock),
        };
        table::add(&mut marketplace.trades, share_nft_id, trade);
        
        // Delete the listing UID to consume it
        object::delete(listing_id_uid);
        
        event::emit(DNFTBought {
            share_nft_id: object::uid_to_inner(&share_nft.id),
            buyer: tx_context::sender(ctx),
            seller,
            price: total_price,
            affiliate_commission,
            app_commission,
        });
        
        (share_nft, commission)
    }

    // FIXED: Properly consume listing by extracting data and deleting UID
    public fun cancel_listing(
        marketplace: &mut VillaMarketplace,
        listing_id: ID,
        _clock: &Clock,
        ctx: &mut TxContext
    ) {
        let listing = table::remove(&mut marketplace.listings, listing_id);
        
        // Extract data from listing (this consumes the listing)
        let DNFTListing {
            id: listing_id_uid,
            share_nft_id: _,
            project_id: _,
            villa_id: _,
            seller,
            price: _,
            affiliate_code: _,
            is_active: _,
            created_at: _,
            expires_at: _,
        } = listing;
        
        assert!(seller == tx_context::sender(ctx), ENotAuthorized);
        
        // Delete the listing UID to consume it
        object::delete(listing_id_uid);
    }

    // ===== Commission and Reward System =====

    public fun create_affiliate_reward(
        _app_cap: &AppCap,
        affiliate_code: String,
        owner: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): AffiliateReward {
        AffiliateReward {
            id: object::new(ctx),
            affiliate_code,
            owner,
            total_earned: 0,
            total_paid: 0,
            pending_amount: 0,
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        }
    }

    public fun create_app_treasury(
        _app_cap: &AppCap,
        project_id: String,
        clock: &Clock,
        ctx: &mut TxContext
    ): AppTreasury {
        AppTreasury {
            id: object::new(ctx),
            project_id,
            total_earned: 0,
            total_paid: 0,
            pending_amount: 0,
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        }
    }

    public fun distribute_commission(
        _app_cap: &AppCap,
        affiliate_reward: &mut AffiliateReward,
        app_treasury: &mut AppTreasury,
        commission: SaleCommission,
        clock: &Clock
    ) {
        affiliate_reward.total_earned = affiliate_reward.total_earned + commission.affiliate_commission;
        affiliate_reward.pending_amount = affiliate_reward.pending_amount + commission.affiliate_commission;
        affiliate_reward.updated_at = clock::timestamp_ms(clock);

        app_treasury.total_earned = app_treasury.total_earned + commission.app_commission;
        app_treasury.pending_amount = app_treasury.pending_amount + commission.app_commission;
        app_treasury.updated_at = clock::timestamp_ms(clock);

        event::emit(AffiliateRewardEarned {
            affiliate_code: affiliate_reward.affiliate_code,
            owner: affiliate_reward.owner,
            amount: commission.affiliate_commission,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    public fun claim_affiliate_reward(
        affiliate_reward: &mut AffiliateReward,
        clock: &Clock,
        ctx: &mut TxContext
    ): u64 {
        assert!(affiliate_reward.owner == tx_context::sender(ctx), ENotAuthorized);
        
        let claimable_amount = affiliate_reward.pending_amount;
        affiliate_reward.total_paid = affiliate_reward.total_paid + claimable_amount;
        affiliate_reward.pending_amount = 0;
        affiliate_reward.updated_at = clock::timestamp_ms(clock);

        event::emit(CommissionPaid {
            recipient: affiliate_reward.owner,
            amount: claimable_amount,
            timestamp: clock::timestamp_ms(clock),
        });

        claimable_amount
    }

    public fun claim_app_commission(
        _app_cap: &AppCap,
        app_treasury: &mut AppTreasury,
        clock: &Clock,
        ctx: &mut TxContext
    ): u64 {
        let claimable_amount = app_treasury.pending_amount;
        app_treasury.total_paid = app_treasury.total_paid + claimable_amount;
        app_treasury.pending_amount = 0;
        app_treasury.updated_at = clock::timestamp_ms(clock);

        event::emit(CommissionPaid {
            recipient: tx_context::sender(ctx),
            amount: claimable_amount,
            timestamp: clock::timestamp_ms(clock),
        });

        claimable_amount
    }

    // ===== Utility Functions =====

    fun generate_affiliate_code(_owner: address, clock: &Clock, _ctx: &mut TxContext): String {
        let timestamp = clock::timestamp_ms(clock);
        let _random_part = timestamp % 10000;
        string::utf8(b"AF")
    }

    public fun update_villa_metadata(
        _asset_manager_cap: &AssetManagerCap,
        villa_metadata: &mut VillaMetadata,
        new_image_url: String,
        new_description: String,
        clock: &Clock
    ) {
        villa_metadata.image_url = new_image_url;
        villa_metadata.description = new_description;
        villa_metadata.updated_at = clock::timestamp_ms(clock);
    }

    // ===== Getters =====

    public fun get_project_info(project: &VillaProject): (String, String, u64, u64, u64) {
        (project.project_id, project.name, project.total_villas, project.max_total_shares, project.total_shares_issued)
    }

    public fun get_villa_info(villa_metadata: &VillaMetadata): (String, String, u64, u64, u64) {
        (villa_metadata.villa_id, villa_metadata.name, villa_metadata.max_shares, villa_metadata.shares_issued, villa_metadata.price_per_share)
    }

    public fun get_share_nft_info(share_nft: &VillaShareNFT): (String, String, address, String, bool) {
        (share_nft.project_id, share_nft.villa_id, share_nft.owner, share_nft.affiliate_code, share_nft.is_affiliate_active)
    }

    public fun get_marketplace_info(marketplace: &VillaMarketplace): (String, u64, u64, u64) {
        (marketplace.project_id, marketplace.commission_rate, marketplace.affiliate_rate, marketplace.created_at)
    }

    public fun get_affiliate_reward_info(affiliate_reward: &AffiliateReward): (String, address, u64, u64, u64) {
        (affiliate_reward.affiliate_code, affiliate_reward.owner, affiliate_reward.total_earned, affiliate_reward.total_paid, affiliate_reward.pending_amount)
    }

    public fun get_app_treasury_info(app_treasury: &AppTreasury): (String, u64, u64, u64) {
        (app_treasury.project_id, app_treasury.total_earned, app_treasury.total_paid, app_treasury.pending_amount)
    }
}
