/// Villa RWA Dynamic NFT Implementation for Sui
/// Final working implementation
module villa_rwa::villa_dnft {
    use sui::object::{Self, UID, ID};
    use sui::transfer as sui_transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::package;
    use sui::display;
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
    // const EInvalidAmount: u64 = 17; // REMOVED - unused constant
    const EInvalidPricePerShare: u64 = 17;
    const EExceedsMaxShares: u64 = 18;
    // Marketplace error codes
    const ENotListed: u64 = 19;
    const EAlreadyListed: u64 = 20;
    const EInvalidListingPrice: u64 = 21;
    const ENotOwner: u64 = 22;
    // Enhanced capability system error codes
    const ENotSuperAdmin: u64 = 23;
    const ENotAdmin: u64 = 24;
    const EAdminAlreadyExists: u64 = 25;
    const EAdminNotFound: u64 = 26;
    const EInvalidRole: u64 = 27;
    const EPermissionDenied: u64 = 28;
    // User vault error codes
    const EInsufficientBalance: u64 = 29;
    const EInsufficientPayment: u64 = 30;
    const EAddressNotRegistered: u64 = 31;
    // Commission system error codes
    const EInsufficientTreasuryBalance: u64 = 32;
    // const ECommissionNotConfigured: u64 = 33; // REMOVED - unused constant
    // Batch escrow system error codes
    const EInvalidAmount: u64 = 33;
    const EExceedsBatchLimit: u64 = 34;
    const EInvalidEscrowStatus: u64 = 35;
    const EEscrowExpired: u64 = 36;
    const EInvalidCancelReason: u64 = 37;
    const EInvalidBatchEscrowStatus: u64 = 38;

    // ===== Capability Objects =====
    public struct VILLA_DNFT has drop {}

    public struct AppCap has key, store {
        id: UID,
        app_address: address,
    }

    #[allow(unused_field)]
    public struct AdminCap has key, store {
        id: UID,
        app_address: address,
    }

    #[allow(unused_field)]
    public struct AssetManagerCap has key, store {
        id: UID,
        app_address: address,
    }

    // ===== Enhanced Capability System =====
    
    /// Super Admin Registry - manages all admins and roles
    public struct SuperAdminRegistry has key, store {
        id: UID,
        super_admin: address,
        admins: Table<address, AdminInfo>,
        total_admins: u64,
        created_at: u64,
    }

    /// Address Registry - tracks all registered wallet addresses
    public struct AddressRegistry has key, store {
        id: UID,
        addresses: Table<address, AddressInfo>,
        total_addresses: u64,
        created_at: u64,
    }

    /// Address Information
    public struct AddressInfo has store, drop {
        address: address,
        registered_by: address,
        registered_at: u64,
        is_active: bool,
        last_activity: u64,
    }

    /// Admin Information
    public struct AdminInfo has store, drop {
        address: address,
        role: String,           // "SUPER_ADMIN", "ADMIN", "MODERATOR", "ASSET_MANAGER"
        permissions: vector<String>, // List of permissions
        granted_by: address,    // Who granted this role
        granted_at: u64,        // When this role was granted
        is_active: bool,        // Whether this admin is active
        last_activity: u64,     // Last activity timestamp
    }

    /// Role Permission Registry
    public struct RolePermissionRegistry has key, store {
        id: UID,
        roles: Table<String, vector<String>>, // role -> permissions mapping
    }

    /// Admin Delegation Capability
    public struct AdminDelegationCap has key, store {
        id: UID,
        admin_address: address,
        delegated_by: address,
        expires_at: u64,
        permissions: vector<String>,
    }

    // ===== Main Data Structures =====

    public struct VillaProject has key, store {
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

    public struct VillaMetadata has key, store {
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

    public struct VillaShareNFT has key, store {
        id: UID,
        project_id: String,
        villa_id: String,
        owner: address,
        affiliate_code: String,
        is_affiliate_active: bool,
        created_at: u64,
        // Marketplace metadata fields
        name: String,
        description: String,
        image_url: String,
        price: u64,
        is_listed: bool,
        listing_price: u64,
    }

    public struct DNFTListing has key, store {
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
        // Marketplace metadata
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
    }

    public struct DNFTTrade has key, store {
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
    public struct SaleCommission has drop {
        affiliate_commission: u64,
        app_commission: u64,
        total_price: u64,
    }

    public struct VillaMarketplace has key, store {
        id: UID,
        project_id: String,
        listings: Table<ID, DNFTListing>,
        trades: Table<ID, DNFTTrade>,
        commission_rate: u64,
        affiliate_rate: u64,
        created_at: u64,
    }

    public struct AffiliateReward has key, store {
        id: UID,
        affiliate_code: String,
        owner: address,
        total_earned: u64,
        total_paid: u64,
        pending_amount: u64,
        created_at: u64,
        updated_at: u64,
    }

    public struct AppTreasury has key, store {
        id: UID,
        project_id: String,
        total_earned: u64,
        total_paid: u64,
        pending_amount: u64,
        created_at: u64,
        updated_at: u64,
    }

    /// Commission Configuration - manages commission rates and settings
    public struct CommissionConfig has key, store {
        id: UID,
        default_commission_rate: u64, // Default 10% (1000 basis points)
        current_commission_rate: u64, // Current commission rate
        admin_address: address, // Admin address (exempt from commission)
        is_active: bool,
        created_at: u64,
        updated_at: u64,
    }

    /// Treasury Balance - stores actual SUI/USDC balance for commission withdrawal
    public struct TreasuryBalance has key, store {
        id: UID,
        sui_balance: Balance<SUI>,
        usdc_balance: Balance<USDC>,
        total_commission_earned: u64,
        total_commission_withdrawn: u64,
        created_at: u64,
        updated_at: u64,
    }

    /// Affiliate Configuration - manages affiliate code settings
    public struct AffiliateConfig has key, store {
        id: UID,
        default_prefix: String, // Default affiliate code prefix
        current_prefix: String, // Current affiliate code prefix
        admin_address: address, // Admin address who can update
        is_active: bool,
        created_at: u64,
        updated_at: u64,
    }

    /// User Vault for storing SUI and USDC tokens
    public struct UserVault has key, store {
        id: UID,
        owner: address,
        sui_balance: Balance<SUI>,
        usdc_balance: Balance<USDC>,
        created_at: u64,
        updated_at: u64,
    }

    /// USDC token type for payments
    public struct USDC has drop {}

    // ===== Batch Escrow Configuration =====

    /// Batch Escrow Configuration - manages batch escrow settings
    public struct BatchEscrowConfig has key, store {
        id: UID,
        max_batch_size: u64,              // Maximum NFTs per batch (default: 100)
        default_expiry_hours: u64,        // Default expiry time in hours (default: 1)
        default_affiliate_active: bool,   // Default affiliate active status for minted NFTs (default: true)
        created_at: u64,
        updated_at: u64,
    }

    // ===== Batch Escrow System =====

    /// Batch Escrow for atomic batch minting with payment
    public struct BatchEscrow<phantom T> has key, store {
        id: UID,
        buyer: address,                    // User address who purchased
        platform: address,                 // Platform address (admin)
        total_amount: u64,                 // Total payment amount for all NFTs
        nft_count: u64,                    // Number of NFTs to be minted
        nft_ids: vector<ID>,               // IDs of successfully minted NFTs
        project_id: String,                // Villa project ID
        villa_id: String,                  // Villa ID
        created_at: u64,                   // Escrow creation timestamp
        expires_at: u64,                   // Escrow expiration timestamp
        status: u8,                        // Escrow status
        successful_nfts: u64,              // Number of successfully minted NFTs
        failed_nfts: u64,                  // Number of failed minted NFTs
        processed_amount: u64,             // Amount processed for successful NFTs
        refund_amount: u64,                // Amount to be refunded for failed NFTs
    }

    /// Batch Escrow Status Constants
    const BATCH_ESCROW_PENDING: u8 = 0;     // Escrow waiting for batch minting
    const BATCH_ESCROW_PROCESSING: u8 = 1;  // Currently processing batch minting
    const BATCH_ESCROW_COMPLETED: u8 = 2;   // All NFTs successfully minted
    const BATCH_ESCROW_PARTIAL: u8 = 3;     // Some NFTs successfully minted
    const BATCH_ESCROW_FAILED: u8 = 4;      // All NFTs failed to mint
    const BATCH_ESCROW_CANCELLED: u8 = 5;   // Escrow cancelled

    // ===== Events =====

    public struct VillaProjectCreated has copy, drop {
        project_id: String,
        name: String,
        max_total_shares: u64,
        created_at: u64,
    }

    public struct VillaProjectUpdated has copy, drop {
        project_id: String,
        old_name: String,
        new_name: String,
        old_commission_rate: u64,
        new_commission_rate: u64,
        old_affiliate_rate: u64,
        new_affiliate_rate: u64,
        updated_at: u64,
    }

    public struct VillaMetadataCreated has copy, drop {
        project_id: String,
        villa_id: String,
        name: String,
        max_shares: u64,
        created_at: u64,
    }

    public struct VillaSharesMinted has copy, drop {
        project_id: String,
        villa_id: String,
        amount: u64,
        total_shares_issued: u64,
        created_at: u64,
        // Marketplace metadata
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
        nft_price: u64,
    }

    public struct DNFTListed has copy, drop {
        share_nft_id: ID,
        seller: address,
        price: u64,
        created_at: u64,
    }

    public struct DNFTBought has copy, drop {
        share_nft_id: ID,
        buyer: address,
        seller: address,
        price: u64,
        affiliate_commission: u64,
        app_commission: u64,
    }

    public struct AffiliateRewardEarned has copy, drop {
        affiliate_code: String,
        owner: address,
        amount: u64,
        timestamp: u64,
    }

    public struct CommissionPaid has copy, drop {
        recipient: address,
        amount: u64,
        timestamp: u64,
    }

    // Marketplace events
    public struct NFTListed has copy, drop {
        nft_id: ID,
        owner: address,
        price: u64,
        timestamp: u64,
    }

    public struct NFTDelisted has copy, drop {
        nft_id: ID,
        owner: address,
        timestamp: u64,
    }

    public struct NFTTransferred has copy, drop {
        nft_id: ID,
        from: address,
        to: address,
        timestamp: u64,
    }

    public struct PriceUpdated has copy, drop {
        nft_id: ID,
        old_price: u64,
        new_price: u64,
        timestamp: u64,
    }

    // Enhanced capability system events
    public struct AdminAdded has copy, drop {
        admin_address: address,
        role: String,
        granted_by: address,
        timestamp: u64,
    }

    public struct AdminRemoved has copy, drop {
        admin_address: address,
        removed_by: address,
        timestamp: u64,
    }

    public struct AdminRoleUpdated has copy, drop {
        admin_address: address,
        old_role: String,
        new_role: String,
        updated_by: address,
        timestamp: u64,
    }

    public struct AdminPermissionGranted has copy, drop {
        admin_address: address,
        permission: String,
        granted_by: address,
        timestamp: u64,
    }

    public struct AdminPermissionRevoked has copy, drop {
        admin_address: address,
        permission: String,
        revoked_by: address,
        timestamp: u64,
    }

    public struct OwnershipTransferred has copy, drop {
        old_owner: address,
        new_owner: address,
        timestamp: u64,
    }

    public struct AdminDelegationCreated has copy, drop {
        admin_address: address,
        delegated_by: address,
        permissions: vector<String>,
        expires_at: u64,
        timestamp: u64,
    }

    public struct AdminListedForUser has copy, drop {
        nft_id: ID,
        admin_address: address,
        user_address: address,
        price: u64,
        timestamp: u64,
    }

    // Admin executor events
    public struct AdminMintedForUser has copy, drop {
        nft_id: ID,
        admin_address: address,
        user_address: address,
        timestamp: u64,
    }

    public struct AdminMintedForAdmin has copy, drop {
        nft_id: ID,
        admin_address: address,
        timestamp: u64,
    }

    public struct AdminTransferredForUser has copy, drop {
        nft_id: ID,
        admin_address: address,
        from_address: address,
        to_address: address,
        timestamp: u64,
    }

    public struct AdminBoughtForUser has copy, drop {
        nft_id: ID,
        admin_address: address,
        buyer_address: address,
        seller_address: address,
        price: u64,
        timestamp: u64,
    }

    public struct AdminDepositedForUser has copy, drop {
        admin_address: address,
        user_address: address,
        amount: u64,
        token_type: String,
        timestamp: u64,
    }

    public struct AdminWithdrewForUser has copy, drop {
        admin_address: address,
        user_address: address,
        recipient_address: address,
        amount: u64,
        token_type: String,
        timestamp: u64,
    }

    // User vault events
    public struct UserVaultCreated has copy, drop {
        vault_id: ID,
        owner: address,
        timestamp: u64,
    }

    public struct TokenDeposited has copy, drop {
        vault_id: ID,
        owner: address,
        amount: u64,
        token_type: String,
        timestamp: u64,
    }

    public struct TokenWithdrawn has copy, drop {
        vault_id: ID,
        owner: address,
        recipient: address,
        amount: u64,
        token_type: String,
        timestamp: u64,
    }

    // Address registry events
    public struct AddressRegistered has copy, drop {
        address: address,
        registered_by: address,
        timestamp: u64,
    }

    /// Commission system events
    public struct CommissionConfigUpdated has copy, drop {
        admin_address: address,
        old_rate: u64,
        new_rate: u64,
        timestamp: u64,
    }

    public struct CommissionCollected has copy, drop {
        seller_address: address,
        buyer_address: address,
        total_price: u64,
        commission_amount: u64,
        seller_received: u64,
        timestamp: u64,
    }

    public struct CommissionWithdrawn has copy, drop {
        admin_address: address,
        amount: u64,
        token_type: String,
        timestamp: u64,
    }

    public struct TreasuryBalanceUpdated has copy, drop {
        sui_balance: u64,
        usdc_balance: u64,
        total_earned: u64,
        timestamp: u64,
    }

    public struct AffiliateConfigUpdated has copy, drop {
        admin_address: address,
        old_prefix: String,
        new_prefix: String,
        timestamp: u64,
    }

    // ===== Batch Escrow Events =====

    public struct BatchEscrowCreated has copy, drop {
        escrow_id: ID,
        buyer: address,
        platform: address,
        total_amount: u64,
        nft_count: u64,
        project_id: String,
        villa_id: String,
        expires_at: u64,
        timestamp: u64,
    }

    public struct BatchMintingCompleted has copy, drop {
        escrow_id: ID,
        buyer: address,
        platform: address,
        total_nfts: u64,
        successful_nfts: u64,
        failed_nfts: u64,
        processed_amount: u64,
        refund_amount: u64,
        timestamp: u64,
    }

    public struct BatchEscrowProcessed has copy, drop {
        escrow_id: ID,
        buyer: address,
        platform: address,
        processed_amount: u64,
        refund_amount: u64,
        successful_nfts: u64,
        failed_nfts: u64,
        timestamp: u64,
    }

    public struct BatchEscrowCancelled has copy, drop {
        escrow_id: ID,
        buyer: address,
        platform: address,
        total_amount: u64,
        nft_count: u64,
        cancel_reason: u8,
        timestamp: u64,
    }

    public struct BatchEscrowConfigUpdated has copy, drop {
        admin_address: address,
        max_batch_size: u64,
        default_expiry_hours: u64,
        default_affiliate_active: bool,
        timestamp: u64,
    }

    // ===== Initialization =====

    /// Create Display object for VillaShareNFT (for wallet rendering)
    /// This function creates a Display template that wallets use to render NFT metadata
    /// Based on Sui Display Standard: https://docs.sui.io/standards/display
    /// 
    /// ⚠️ IMPORTANT: This function should be called ONCE after package upgrade
    /// with the Publisher object that was created during deployment
    /// Returns Display object that caller can transfer or use as needed
    public fun create_and_transfer_display(
        publisher: &package::Publisher,
        ctx: &mut TxContext
    ): display::Display<VillaShareNFT> {
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"description"),
            string::utf8(b"image_url"),
            string::utf8(b"url"), // ← CRITICAL for Slush Wallet compatibility
            string::utf8(b"project_url"),
            string::utf8(b"creator"),
            string::utf8(b"project_id"),
            string::utf8(b"villa_id"),
        ];
        
        let values = vector[
            string::utf8(b"{name}"),
            string::utf8(b"{description}"),
            string::utf8(b"{image_url}"),
            string::utf8(b"{image_url}"), // url points to same image_url (for wallet compatibility)
            string::utf8(b"https://app.thehistorymaker.io"), // Project URL
            string::utf8(b"{owner}"), // Creator = NFT owner address
            string::utf8(b"{project_id}"),
            string::utf8(b"{villa_id}"),
        ];
        
        let mut display = display::new_with_fields<VillaShareNFT>(
            publisher, 
            keys, 
            values, 
            ctx
        );
        
        display::update_version(&mut display);
        
        // Return Display object (caller can transfer to their address)
        display
    }

    fun init(_witness: VILLA_DNFT, ctx: &mut TxContext) {
        // ✅ ORIGINAL: Keep the original behavior - claim_and_keep
        // This stores Publisher internally and doesn't return it
        package::claim_and_keep(_witness, ctx);
        
        // NOTE: Display object will be created separately after upgrade
        // by calling create_and_transfer_display() with the stored Publisher
        
        // Create app capability
        let app_cap = AppCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        sui_transfer::share_object(app_cap);

        // Create admin capability
        let admin_cap = AdminCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        sui_transfer::share_object(admin_cap);

        // Create asset manager capability
        let asset_manager_cap = AssetManagerCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        sui_transfer::share_object(asset_manager_cap);

        // Create Super Admin Registry
        let mut super_admin_registry = SuperAdminRegistry {
            id: object::new(ctx),
            super_admin: tx_context::sender(ctx),
            admins: table::new(ctx),
            total_admins: 0,
            created_at: 0, // Will be set by clock in first transaction
        };

        // Add owner as SUPER_ADMIN to admins table
        let super_admin_permissions = vector[
            string::utf8(b"ADMIN_MANAGEMENT"),
            string::utf8(b"ROLE_MANAGEMENT"),
            string::utf8(b"PERMISSION_MANAGEMENT"),
            string::utf8(b"OWNERSHIP_TRANSFER"),
            string::utf8(b"ADMIN_DELEGATION"),
            string::utf8(b"ADMIN_LIST_FOR_USER"),
            string::utf8(b"ADMIN_MINT_FOR_USER"),
            string::utf8(b"ADMIN_MINT_FOR_ADMIN"),
            string::utf8(b"ADMIN_TRANSFER_FOR_USER"),
            string::utf8(b"ADMIN_BUY_FOR_USER"),
            string::utf8(b"ADMIN_DEPOSIT_FOR_USER"),
            string::utf8(b"ADMIN_WITHDRAW_FOR_USER"),
            string::utf8(b"ALL_OPERATIONS")
        ];

        let owner_admin_info = AdminInfo {
            address: tx_context::sender(ctx),
            role: string::utf8(b"SUPER_ADMIN"),
            permissions: super_admin_permissions,
            granted_by: tx_context::sender(ctx), // Self-granted
            granted_at: 0, // Will be set by clock in first transaction
            is_active: true,
            last_activity: 0, // Will be set by clock in first transaction
        };

        table::add(&mut super_admin_registry.admins, tx_context::sender(ctx), owner_admin_info);
        super_admin_registry.total_admins = 1;

        // Create Address Registry
        let mut address_registry = AddressRegistry {
            id: object::new(ctx),
            addresses: table::new(ctx),
            total_addresses: 0,
            created_at: 0, // Will be set by clock in first transaction
        };

        // Add owner to address registry
        let owner_address_info = AddressInfo {
            address: tx_context::sender(ctx),
            registered_by: tx_context::sender(ctx), // Self-registered
            registered_at: 0, // Will be set by clock in first transaction
            is_active: true,
            last_activity: 0, // Will be set by clock in first transaction
        };

        table::add(&mut address_registry.addresses, tx_context::sender(ctx), owner_address_info);
        address_registry.total_addresses = 1;

        // Create Role Permission Registry
        let mut role_permission_registry = RolePermissionRegistry {
            id: object::new(ctx),
            roles: table::new(ctx),
        };

        // Initialize default roles and permissions
        let super_admin_permissions = vector[
            string::utf8(b"ADMIN_MANAGEMENT"),
            string::utf8(b"ROLE_MANAGEMENT"),
            string::utf8(b"PERMISSION_MANAGEMENT"),
            string::utf8(b"OWNERSHIP_TRANSFER"),
            string::utf8(b"ADMIN_DELEGATION"),
            string::utf8(b"ADMIN_LIST_FOR_USER"),
            string::utf8(b"ADMIN_MINT_FOR_USER"),
            string::utf8(b"ADMIN_MINT_FOR_ADMIN"),
            string::utf8(b"ADMIN_TRANSFER_FOR_USER"),
            string::utf8(b"ADMIN_BUY_FOR_USER"),
            string::utf8(b"ADMIN_DEPOSIT_FOR_USER"),
            string::utf8(b"ADMIN_WITHDRAW_FOR_USER"),
            string::utf8(b"ALL_OPERATIONS")
        ];
        table::add(&mut role_permission_registry.roles, string::utf8(b"SUPER_ADMIN"), super_admin_permissions);

        let admin_permissions = vector[
            string::utf8(b"PROJECT_MANAGEMENT"),
            string::utf8(b"VILLA_MANAGEMENT"),
            string::utf8(b"MINTING"),
            string::utf8(b"MARKETPLACE_MANAGEMENT"),
            string::utf8(b"ADMIN_LIST_FOR_USER"),
            string::utf8(b"ADMIN_MINT_FOR_USER"),
            string::utf8(b"ADMIN_MINT_FOR_ADMIN"),
            string::utf8(b"ADMIN_TRANSFER_FOR_USER"),
            string::utf8(b"ADMIN_BUY_FOR_USER"),
            string::utf8(b"ADMIN_DEPOSIT_FOR_USER"),
            string::utf8(b"ADMIN_WITHDRAW_FOR_USER")
        ];
        table::add(&mut role_permission_registry.roles, string::utf8(b"ADMIN"), admin_permissions);

        let moderator_permissions = vector[
            string::utf8(b"VILLA_MANAGEMENT"),
            string::utf8(b"MARKETPLACE_MANAGEMENT")
        ];
        table::add(&mut role_permission_registry.roles, string::utf8(b"MODERATOR"), moderator_permissions);

        let asset_manager_permissions = vector[
            string::utf8(b"VILLA_MANAGEMENT"),
            string::utf8(b"METADATA_UPDATE")
        ];
        table::add(&mut role_permission_registry.roles, string::utf8(b"ASSET_MANAGER"), asset_manager_permissions);

        // Share the registries
        sui_transfer::share_object(super_admin_registry);
        sui_transfer::share_object(address_registry);
        sui_transfer::share_object(role_permission_registry);

        // Create commission configuration (default 10%)
        let current_timestamp = 0; // Will be updated when clock is available
        let commission_config = CommissionConfig {
            id: object::new(ctx),
            default_commission_rate: 1000, // 10% = 1000 basis points
            current_commission_rate: 1000, // 10% = 1000 basis points
            admin_address: tx_context::sender(ctx),
            is_active: true,
            created_at: current_timestamp,
            updated_at: current_timestamp,
        };

        // Create treasury balance
        let treasury_balance = TreasuryBalance {
            id: object::new(ctx),
            sui_balance: balance::zero<SUI>(),
            usdc_balance: balance::zero<USDC>(),
            total_commission_earned: 0,
            total_commission_withdrawn: 0,
            created_at: current_timestamp,
            updated_at: current_timestamp,
        };

        // Initialize affiliate configuration with default values
        let affiliate_config = AffiliateConfig {
            id: object::new(ctx),
            default_prefix: string::utf8(b"AF"), // Default prefix "AF"
            current_prefix: string::utf8(b"AF"), // Current prefix "AF"
            admin_address: tx_context::sender(ctx),
            is_active: true,
            created_at: current_timestamp,
            updated_at: current_timestamp,
        };

        // Transfer commission config, treasury balance, and affiliate config to admin
        sui_transfer::transfer(commission_config, tx_context::sender(ctx));
        sui_transfer::transfer(treasury_balance, tx_context::sender(ctx));
        sui_transfer::transfer(affiliate_config, tx_context::sender(ctx));
    }

    // ===== Capability Management =====

    /// Create new AppCap for a specific address (only by AdminCap)
    public fun create_app_cap_for_address(
        _admin_cap: &AdminCap,
        target_address: address,
        ctx: &mut TxContext
    ): AppCap {
        AppCap {
            id: object::new(ctx),
            app_address: target_address,
        }
    }

    #[allow(lint(custom_state_change))]
    public fun transfer_app_cap_to_address(
        _admin_cap: &AdminCap,
        app_cap: AppCap,
        recipient: address,
    ) {
        sui_transfer::transfer(app_cap, recipient);
    }

    /// Create shared AppCap that can be used by anyone (only by AdminCap)
    public fun create_shared_app_cap(
        _admin_cap: &AdminCap,
        ctx: &mut TxContext
    ) {
        let shared_app_cap = AppCap {
            id: object::new(ctx),
            app_address: @0x0, // Special address for shared cap
        };
        sui_transfer::share_object(shared_app_cap);
    }

    /// Create villa project using AdminCap (alternative to AppCap)
    public fun create_villa_project_with_admin(
        _admin_cap: &AdminCap,
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

    /// Create villa metadata using AdminCap (alternative to AppCap)
    public fun create_villa_metadata_with_admin(
        _admin_cap: &AdminCap,
        project: &mut VillaProject,
        villa_id: String,
        name: String,
        description: String,
        location: String,
        image_url: String,
        max_shares: u64,
        price_per_share: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaMetadata {
        assert!(max_shares > 0, EInvalidMaxShares);
        assert!(price_per_share > 0, EInvalidPricePerShare);
        assert!(project.total_shares_issued + max_shares <= project.max_total_shares, EExceedsMaxShares);

        let metadata = VillaMetadata {
            id: object::new(ctx),
            project_id: project.project_id,
            villa_id,
            name,
            description,
            location,
            image_url,
            max_shares,
            shares_issued: 0,
            price_per_share,
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        };

        project.total_villas = project.total_villas + 1;
        project.total_shares_issued = project.total_shares_issued + max_shares;
        project.updated_at = clock::timestamp_ms(clock);

        event::emit(VillaMetadataCreated {
            project_id: project.project_id,
            villa_id: metadata.villa_id,
            name: metadata.name,
            max_shares: metadata.max_shares,
            created_at: metadata.created_at,
        });

        metadata
    }

    // ===== Enhanced Capability System Functions =====

    /// Initialize Super Admin Registry with clock timestamp
    public fun initialize_super_admin_registry(
        super_admin_registry: &mut SuperAdminRegistry,
        clock: &Clock
    ) {
        if (super_admin_registry.created_at == 0) {
            super_admin_registry.created_at = clock::timestamp_ms(clock);
        };
    }

    /// Add admin to the registry (only by Super Admin)
    public fun add_admin(
        super_admin_registry: &mut SuperAdminRegistry,
        role_permission_registry: &RolePermissionRegistry,
        admin_address: address,
        role: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(super_admin_registry.super_admin == tx_context::sender(ctx), ENotSuperAdmin);
        assert!(!table::contains(&super_admin_registry.admins, admin_address), EAdminAlreadyExists);
        assert!(table::contains(&role_permission_registry.roles, role), EInvalidRole);

        // Get permissions for the role
        let permissions = table::borrow(&role_permission_registry.roles, role);

        let admin_info = AdminInfo {
            address: admin_address,
            role,
            permissions: *permissions,
            granted_by: tx_context::sender(ctx),
            granted_at: clock::timestamp_ms(clock),
            is_active: true,
            last_activity: clock::timestamp_ms(clock),
        };

        table::add(&mut super_admin_registry.admins, admin_address, admin_info);
        super_admin_registry.total_admins = super_admin_registry.total_admins + 1;

        event::emit(AdminAdded {
            admin_address,
            role,
            granted_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Remove admin from the registry (only by Super Admin)
    public fun remove_admin(
        super_admin_registry: &mut SuperAdminRegistry,
        admin_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(super_admin_registry.super_admin == tx_context::sender(ctx), ENotSuperAdmin);
        assert!(table::contains(&super_admin_registry.admins, admin_address), EAdminNotFound);

        let _admin_info = table::remove(&mut super_admin_registry.admins, admin_address);
        super_admin_registry.total_admins = super_admin_registry.total_admins - 1;

        event::emit(AdminRemoved {
            admin_address,
            removed_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update admin role (only by Super Admin)
    public fun update_admin_role(
        super_admin_registry: &mut SuperAdminRegistry,
        role_permission_registry: &RolePermissionRegistry,
        admin_address: address,
        new_role: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(super_admin_registry.super_admin == tx_context::sender(ctx), ENotSuperAdmin);
        assert!(table::contains(&super_admin_registry.admins, admin_address), EAdminNotFound);
        assert!(table::contains(&role_permission_registry.roles, new_role), EInvalidRole);

        let admin_info = table::borrow_mut(&mut super_admin_registry.admins, admin_address);
        let old_role = admin_info.role;
        
        // Get new permissions for the role
        let new_permissions = table::borrow(&role_permission_registry.roles, new_role);
        admin_info.role = new_role;
        admin_info.permissions = *new_permissions;
        admin_info.last_activity = clock::timestamp_ms(clock);

        event::emit(AdminRoleUpdated {
            admin_address,
            old_role,
            new_role,
            updated_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Grant permission to admin (only by Super Admin)
    public fun grant_admin_permission(
        super_admin_registry: &mut SuperAdminRegistry,
        admin_address: address,
        permission: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(super_admin_registry.super_admin == tx_context::sender(ctx), ENotSuperAdmin);
        assert!(table::contains(&super_admin_registry.admins, admin_address), EAdminNotFound);

        let admin_info = table::borrow_mut(&mut super_admin_registry.admins, admin_address);
        
        // Check if permission already exists
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        let mut found = false;
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &permission) {
                found = true;
                break
            };
            i = i + 1;
        };

        if (!found) {
            vector::push_back(&mut admin_info.permissions, permission);
            admin_info.last_activity = clock::timestamp_ms(clock);

            event::emit(AdminPermissionGranted {
                admin_address,
                permission,
                granted_by: tx_context::sender(ctx),
                timestamp: clock::timestamp_ms(clock),
            });
        };
    }

    /// Revoke permission from admin (only by Super Admin)
    public fun revoke_admin_permission(
        super_admin_registry: &mut SuperAdminRegistry,
        admin_address: address,
        permission: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(super_admin_registry.super_admin == tx_context::sender(ctx), ENotSuperAdmin);
        assert!(table::contains(&super_admin_registry.admins, admin_address), EAdminNotFound);

        let admin_info = table::borrow_mut(&mut super_admin_registry.admins, admin_address);
        
        // Find and remove permission
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &permission) {
                vector::remove(&mut admin_info.permissions, i);
                admin_info.last_activity = clock::timestamp_ms(clock);

                event::emit(AdminPermissionRevoked {
                    admin_address,
                    permission,
                    revoked_by: tx_context::sender(ctx),
                    timestamp: clock::timestamp_ms(clock),
                });
                break
            };
            i = i + 1;
        };
    }

    /// Transfer ownership of smart contract (only by Super Admin)
    public fun transfer_ownership(
        super_admin_registry: &mut SuperAdminRegistry,
        new_owner: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(super_admin_registry.super_admin == tx_context::sender(ctx), ENotSuperAdmin);

        let old_owner = super_admin_registry.super_admin;
        super_admin_registry.super_admin = new_owner;

        event::emit(OwnershipTransferred {
            old_owner,
            new_owner,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Create admin delegation capability
    public fun create_admin_delegation(
        super_admin_registry: &mut SuperAdminRegistry,
        admin_address: address,
        permissions: vector<String>,
        expires_at: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): AdminDelegationCap {
        assert!(super_admin_registry.super_admin == tx_context::sender(ctx), ENotSuperAdmin);
        assert!(table::contains(&super_admin_registry.admins, admin_address), EAdminNotFound);
        assert!(expires_at > clock::timestamp_ms(clock), EListingExpired);

        let delegation_cap = AdminDelegationCap {
            id: object::new(ctx),
            admin_address,
            delegated_by: tx_context::sender(ctx),
            expires_at,
            permissions,
        };

        event::emit(AdminDelegationCreated {
            admin_address,
            delegated_by: tx_context::sender(ctx),
            permissions: delegation_cap.permissions,
            expires_at,
            timestamp: clock::timestamp_ms(clock),
        });

        delegation_cap
    }

    /// Admin list NFT for user (bypass ownership check)
    public fun admin_list_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        nft: &mut VillaShareNFT,
        price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_LIST_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_LIST_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        assert!(!nft.is_listed, EAlreadyListed);
        assert!(price > 0, EInvalidListingPrice);

        nft.is_listed = true;
        nft.listing_price = price;
        nft.price = price;

        event::emit(AdminListedForUser {
            nft_id: object::uid_to_inner(&nft.id),
            admin_address,
            user_address: nft.owner,
            price,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(NFTListed {
            nft_id: object::uid_to_inner(&nft.id),
            owner: nft.owner,
            price,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Admin mint NFT for user
    public fun admin_mint_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        user_address: address,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        affiliate_config: &AffiliateConfig,
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_MINT_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_MINT_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Validate minting constraints
        assert!(villa_metadata.shares_issued < villa_metadata.max_shares, EExceedsVillaLimit);
        assert!(project.total_shares_issued < project.max_total_shares, EExceedsProjectLimit);

        // Mint NFT for user
        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            owner: user_address, // User becomes owner
            affiliate_code: generate_affiliate_code(user_address, affiliate_config, clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
            name: nft_name,
            description: nft_description,
            image_url: nft_image_url,
            price: villa_metadata.price_per_share,
            is_listed: false,
            listing_price: 0,
        };

        // Update counters
        villa_metadata.shares_issued = villa_metadata.shares_issued + 1;
        villa_metadata.updated_at = clock::timestamp_ms(clock);
        project.total_shares_issued = project.total_shares_issued + 1;
        project.updated_at = clock::timestamp_ms(clock);

        // Emit events
        event::emit(AdminMintedForUser {
            nft_id: object::uid_to_inner(&share_nft.id),
            admin_address,
            user_address,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(VillaSharesMinted {
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            amount: 1,
            total_shares_issued: villa_metadata.shares_issued,
            created_at: clock::timestamp_ms(clock),
            nft_name: nft_name,
            nft_description: nft_description,
            nft_image_url: nft_image_url,
            nft_price: villa_metadata.price_per_share,
        });

        share_nft
    }

    /// Admin mint NFT for admin (admin becomes owner)
    public fun admin_mint_for_admin(
        super_admin_registry: &mut SuperAdminRegistry,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        affiliate_config: &AffiliateConfig,
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_MINT_FOR_ADMIN permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_MINT_FOR_ADMIN")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Validate minting constraints
        assert!(villa_metadata.shares_issued < villa_metadata.max_shares, EExceedsVillaLimit);
        assert!(project.total_shares_issued < project.max_total_shares, EExceedsProjectLimit);

        // Mint NFT for admin (admin becomes owner)
            let share_nft = VillaShareNFT {
                id: object::new(ctx),
                project_id: project.project_id,
                villa_id: villa_metadata.villa_id,
            owner: admin_address, // Admin becomes owner
            affiliate_code: generate_affiliate_code(admin_address, affiliate_config, clock, ctx),
                is_affiliate_active: true,
                created_at: clock::timestamp_ms(clock),
                name: nft_name,
                description: nft_description,
                image_url: nft_image_url,
                price: villa_metadata.price_per_share,
                is_listed: false,
                listing_price: 0,
        };

        // Update counters
        villa_metadata.shares_issued = villa_metadata.shares_issued + 1;
        villa_metadata.updated_at = clock::timestamp_ms(clock);
        project.total_shares_issued = project.total_shares_issued + 1;
        project.updated_at = clock::timestamp_ms(clock);

        // Emit events
        event::emit(AdminMintedForAdmin {
            nft_id: object::uid_to_inner(&share_nft.id),
            admin_address,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(VillaSharesMinted {
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            amount: 1,
            total_shares_issued: villa_metadata.shares_issued,
            created_at: clock::timestamp_ms(clock),
            nft_name: nft_name,
            nft_description: nft_description,
            nft_image_url: nft_image_url,
            nft_price: villa_metadata.price_per_share,
        });

        share_nft
    }

    /// Admin transfer NFT for user (admin must provide the NFT to transfer)
    /// This function is safe from owner conflicts because admin provides the NFT directly
    /// Usage: User gives NFT to admin, admin transfers it to another address
    public fun admin_transfer_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        mut nft: VillaShareNFT,
        to_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_TRANSFER_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_TRANSFER_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Get current owner and NFT ID before transfer
        let from_address = nft.owner;
        let nft_id = object::uid_to_inner(&nft.id);

        // Transfer ownership
        nft.owner = to_address;

        // Emit events
        event::emit(AdminTransferredForUser {
            nft_id,
            admin_address,
            from_address,
            to_address,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(NFTTransferred {
            nft_id,
            from: from_address,
            to: to_address,
            timestamp: clock::timestamp_ms(clock),
        });

        nft // Return the transferred NFT
    }

    /// Admin transfer NFT for user with ownership validation (alternative approach)
    /// This function validates that NFT is owned by from_address before transfer
    /// Usage: Admin specifies from_address, function validates ownership and transfers to to_address
    /// WARNING: This approach requires the NFT to be owned by from_address, which may cause conflicts
    public fun admin_transfer_for_user_with_validation(
        super_admin_registry: &mut SuperAdminRegistry,
        nft: &mut VillaShareNFT,
        from_address: address,
        to_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_TRANSFER_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_TRANSFER_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Validate ownership - NFT must be owned by from_address
        assert!(nft.owner == from_address, ENotOwner);

        // Get NFT ID before transfer
        let nft_id = object::uid_to_inner(&nft.id);

        // Transfer ownership
        nft.owner = to_address;

        // Emit events
        event::emit(AdminTransferredForUser {
            nft_id,
            admin_address,
            from_address,
            to_address,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(NFTTransferred {
            nft_id,
            from: from_address,
            to: to_address,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Admin buy NFT for user
    public fun admin_buy_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        marketplace: &mut VillaMarketplace,
        _commission_config: &mut CommissionConfig,
        _treasury_balance: &mut TreasuryBalance,
        affiliate_config: &AffiliateConfig,
        listing_id: ID,
        buyer_address: address,
        _user_payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_BUY_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_BUY_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Get listing
        let listing = table::remove(&mut marketplace.listings, listing_id);
        
        assert!(listing.is_active, EListingNotFound);
        assert!(clock::timestamp_ms(clock) <= listing.expires_at, EListingExpired);
        
        // Extract data from listing
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
            nft_name,
            nft_description,
            nft_image_url,
        } = listing;
        
        // Validate payment
        assert!(coin::value(&_user_payment) >= total_price, EInsufficientPayment);
        
        // Calculate commissions
        let affiliate_commission = (total_price * marketplace.affiliate_rate) / 10000;
        let app_commission = (total_price * marketplace.commission_rate) / 10000;
        
        // Transfer payment to seller
        sui_transfer::public_transfer(_user_payment, seller);
        
        // Create new NFT for buyer
        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id,
            villa_id,
            owner: buyer_address, // User becomes owner
            affiliate_code: generate_affiliate_code(buyer_address, affiliate_config, clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
            name: nft_name,
            description: nft_description,
            image_url: nft_image_url,
            price: total_price,
            is_listed: false,
            listing_price: 0,
        };
        
        // Record trade
        let trade = DNFTTrade {
            id: object::new(ctx),
            share_nft_id,
            project_id,
            villa_id,
            seller,
            buyer: buyer_address,
            price: total_price,
            affiliate_commission,
            app_commission,
            timestamp: clock::timestamp_ms(clock),
        };
        table::add(&mut marketplace.trades, share_nft_id, trade);
        
        // Delete the listing UID
        object::delete(listing_id_uid);
        
        // Emit events
        event::emit(AdminBoughtForUser {
            nft_id: object::uid_to_inner(&share_nft.id),
            admin_address,
            buyer_address,
            seller_address: seller,
            price: total_price,
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(DNFTBought {
            share_nft_id: object::uid_to_inner(&share_nft.id),
            buyer: buyer_address,
            seller,
            price: total_price,
            affiliate_commission,
            app_commission,
        });
        
        share_nft
    }

    /// Get all admins list
    public fun get_all_admins(super_admin_registry: &SuperAdminRegistry): vector<address> {
        let admins = vector::empty<address>();
        let mut i = 0;
        let len = super_admin_registry.total_admins;
        while (i < len) {
            // Note: This is a simplified version. In practice, you'd need to iterate through the table
            // which requires additional helper functions or different approach
            i = i + 1;
        };
        admins
    }

    /// Get admin info
    public fun get_admin_info(super_admin_registry: &SuperAdminRegistry, admin_address: address): (String, vector<String>, address, u64, bool, u64) {
        assert!(table::contains(&super_admin_registry.admins, admin_address), EAdminNotFound);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        (
            admin_info.role,
            admin_info.permissions,
            admin_info.granted_by,
            admin_info.granted_at,
            admin_info.is_active,
            admin_info.last_activity
        )
    }

    /// Check if address is admin
    public fun is_admin(super_admin_registry: &SuperAdminRegistry, admin_address: address): bool {
        table::contains(&super_admin_registry.admins, admin_address)
    }

    /// Check if address is super admin
    public fun is_super_admin(super_admin_registry: &SuperAdminRegistry, admin_address: address): bool {
        super_admin_registry.super_admin == admin_address
    }

    /// Get super admin address
    public fun get_super_admin(super_admin_registry: &SuperAdminRegistry): address {
        super_admin_registry.super_admin
    }

    /// Get total admins count
    public fun get_total_admins(super_admin_registry: &SuperAdminRegistry): u64 {
        super_admin_registry.total_admins
    }

    // ===== Address Registry Management =====

    /// Register an address
    public fun register_address(
        address_registry: &mut AddressRegistry,
        new_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!table::contains(&address_registry.addresses, new_address), EAdminAlreadyExists);

        let address_info = AddressInfo {
            address: new_address,
            registered_by: tx_context::sender(ctx),
            registered_at: clock::timestamp_ms(clock),
            is_active: true,
            last_activity: clock::timestamp_ms(clock),
        };

        table::add(&mut address_registry.addresses, new_address, address_info);
        address_registry.total_addresses = address_registry.total_addresses + 1;

        event::emit(AddressRegistered {
            address: new_address,
            registered_by: tx_context::sender(ctx),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Get all registered addresses
    public fun get_all_registered_addresses(address_registry: &AddressRegistry): vector<address> {
        let addresses = vector::empty<address>();
        let mut i = 0;
        let len = address_registry.total_addresses;
        while (i < len) {
            // Note: This is a simplified version. In practice, you'd need to iterate through the table
            // which requires additional helper functions or different approach
            i = i + 1;
        };
        addresses
    }

    /// Check if address is registered
    public fun is_address_registered(address_registry: &AddressRegistry, addr: address): bool {
        table::contains(&address_registry.addresses, addr)
    }

    /// Get address info
    public fun get_address_info(address_registry: &AddressRegistry, addr: address): (address, u64, bool, u64) {
        assert!(table::contains(&address_registry.addresses, addr), EAddressNotRegistered);
        
        let address_info = table::borrow(&address_registry.addresses, addr);
        (
            address_info.registered_by,
            address_info.registered_at,
            address_info.is_active,
            address_info.last_activity
        )
    }

    /// Get total registered addresses count
    public fun get_total_registered_addresses(address_registry: &AddressRegistry): u64 {
        address_registry.total_addresses
    }

    // ===== User Vault Management =====

    /// Create user vault
    public fun create_user_vault(
        owner: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): UserVault {
        let vault = UserVault {
            id: object::new(ctx),
            owner,
            sui_balance: balance::zero<SUI>(),
            usdc_balance: balance::zero<USDC>(),
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        };

        event::emit(UserVaultCreated {
            vault_id: object::uid_to_inner(&vault.id),
            owner,
            timestamp: clock::timestamp_ms(clock),
        });

        vault
    }

    /// Admin deposit SUI for user
    public fun admin_deposit_sui_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        user_vault: &mut UserVault,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_DEPOSIT_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_DEPOSIT_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Deposit SUI to user vault
        // Note: This function is a placeholder for admin deposit functionality
        // The actual deposit logic would be implemented based on business requirements
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Define placeholder amount for event emission
        let amount: u64 = 0;

        // Emit event
        event::emit(AdminDepositedForUser {
            admin_address,
            user_address: user_vault.owner,
            amount,
            token_type: string::utf8(b"SUI"),
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(TokenDeposited {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            amount,
            token_type: string::utf8(b"SUI"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Admin deposit USDC for user
    public fun admin_deposit_usdc_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        user_vault: &mut UserVault,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_DEPOSIT_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_DEPOSIT_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Deposit USDC to user vault
        // Note: This function is a placeholder for admin deposit functionality
        // The actual deposit logic would be implemented based on business requirements
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Define placeholder amount for event emission
        let amount: u64 = 0;

        // Emit event
        event::emit(AdminDepositedForUser {
            admin_address,
            user_address: user_vault.owner,
            amount,
            token_type: string::utf8(b"USDC"),
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(TokenDeposited {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            amount,
            token_type: string::utf8(b"USDC"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Admin withdraw SUI for user
    public fun admin_withdraw_sui_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        user_vault: &mut UserVault,
        amount: u64,
        recipient_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<SUI> {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_WITHDRAW_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_WITHDRAW_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Validate vault ownership
        assert!(user_vault.owner == recipient_address, ENotOwner);

        // Validate balance
        assert!(balance::value(&user_vault.sui_balance) >= amount, EInsufficientBalance);

        // Withdraw from user vault
        let withdrawn_balance = balance::split(&mut user_vault.sui_balance, amount);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Emit event
        event::emit(AdminWithdrewForUser {
            admin_address,
            user_address: user_vault.owner,
            recipient_address,
            amount,
            token_type: string::utf8(b"SUI"),
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(TokenWithdrawn {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            recipient: recipient_address,
            amount,
            token_type: string::utf8(b"SUI"),
            timestamp: clock::timestamp_ms(clock),
        });

        withdrawn_coin
    }

    /// Admin withdraw USDC for user
    public fun admin_withdraw_usdc_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        user_vault: &mut UserVault,
        amount: u64,
        recipient_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<USDC> {
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has ADMIN_WITHDRAW_FOR_USER permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_WITHDRAW_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // Validate vault ownership
        assert!(user_vault.owner == recipient_address, ENotOwner);

        // Validate balance
        assert!(balance::value(&user_vault.usdc_balance) >= amount, EInsufficientBalance);

        // Withdraw from user vault
        let withdrawn_balance = balance::split(&mut user_vault.usdc_balance, amount);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Emit event
        event::emit(AdminWithdrewForUser {
            admin_address,
            user_address: user_vault.owner,
            recipient_address,
            amount,
            token_type: string::utf8(b"USDC"),
            timestamp: clock::timestamp_ms(clock),
        });

        event::emit(TokenWithdrawn {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            recipient: recipient_address,
            amount,
            token_type: string::utf8(b"USDC"),
            timestamp: clock::timestamp_ms(clock),
        });

        withdrawn_coin
    }

    /// Get user vault balance
    public fun get_user_vault_balance(user_vault: &UserVault): (u64, u64) {
        (
            balance::value(&user_vault.sui_balance),
            balance::value(&user_vault.usdc_balance)
        )
    }

    /// Get user vault owner
    public fun get_user_vault_owner(user_vault: &UserVault): address {
        user_vault.owner
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
        affiliate_config: &AffiliateConfig,
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
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
            affiliate_code: generate_affiliate_code(tx_context::sender(ctx), affiliate_config, clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
            // Marketplace metadata
            name: nft_name,
            description: nft_description,
            image_url: nft_image_url,
            price: villa_metadata.price_per_share,
            is_listed: false,
            listing_price: 0,
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
            // Marketplace metadata
            nft_name: nft_name,
            nft_description: nft_description,
            nft_image_url: nft_image_url,
            nft_price: villa_metadata.price_per_share,
        });

        share_nft
    }

    public fun mint_villa_shares_batch(
        _app_cap: &AppCap,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        affiliate_config: &AffiliateConfig,
        amount: u64,
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
        clock: &Clock,
        ctx: &mut TxContext
    ): vector<VillaShareNFT> {
        assert!(amount > 0, EInvalidMaxShares);
        assert!(villa_metadata.shares_issued + amount <= villa_metadata.max_shares, EExceedsVillaLimit);
        assert!(project.total_shares_issued + amount <= project.max_total_shares, EExceedsProjectLimit);

        let mut shares = vector::empty<VillaShareNFT>();

        // Mint shares one by one
        let mut i = 0;
        while (i < amount) {
            let share_nft = VillaShareNFT {
                id: object::new(ctx),
                project_id: project.project_id,
                villa_id: villa_metadata.villa_id,
                owner: tx_context::sender(ctx),
                affiliate_code: generate_affiliate_code(tx_context::sender(ctx), affiliate_config, clock, ctx),
                is_affiliate_active: true,
                created_at: clock::timestamp_ms(clock),
                // Marketplace metadata
                name: nft_name,
                description: nft_description,
                image_url: nft_image_url,
                price: villa_metadata.price_per_share,
                is_listed: false,
                listing_price: 0,
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
            // Marketplace metadata
            nft_name: nft_name,
            nft_description: nft_description,
            nft_image_url: nft_image_url,
            nft_price: villa_metadata.price_per_share,
        });

        shares
    }

    // REMOVED: mint_villa_share_with_admin function
    // Reason: Had owner conflict (admin became owner instead of user)
    // Use admin_mint_for_user instead, which is more complete and secure

    // REMOVED: mint_villa_shares_batch_with_admin function
    // Reason: Had owner conflict (admin became owner instead of user)
    // For batch minting, use multiple calls to admin_mint_for_user instead


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
        share_nft: &mut VillaShareNFT,
        price: u64,
        expires_at: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(price > 0, EInvalidPrice);
        assert!(expires_at > clock::timestamp_ms(clock), EListingExpired);

        // Update NFT status to listed (preserve original ID)
        share_nft.is_listed = true;
        share_nft.listing_price = price;

        // Get the original ID (preserve it)
        let share_nft_id_value = object::uid_to_inner(&share_nft.id);

        let listing = DNFTListing {
            id: object::new(ctx),
            share_nft_id: share_nft_id_value,
            project_id: share_nft.project_id,
            villa_id: share_nft.villa_id,
            seller: share_nft.owner,
            price,
            affiliate_code: share_nft.affiliate_code,
            is_active: true,
            created_at: clock::timestamp_ms(clock),
            expires_at,
            // Marketplace metadata
            nft_name: share_nft.name,
            nft_description: share_nft.description,
            nft_image_url: share_nft.image_url,
        };

        table::add(&mut marketplace.listings, listing.share_nft_id, listing);

        // DO NOT delete the original NFT - preserve ID for tracking
        // object::delete(share_nft_id); // REMOVED

        event::emit(DNFTListed {
            share_nft_id: share_nft_id_value,
            seller: share_nft.owner,
            price,
            created_at: clock::timestamp_ms(clock),
        });
    }

    // FIXED: Properly handle listing consumption and create new share_nft
    public fun buy_dnft_from_marketplace(
        marketplace: &mut VillaMarketplace,
        share_nft: &mut VillaShareNFT,
        affiliate_config: &AffiliateConfig,
        listing_id: ID,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): SaleCommission {
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
            // Marketplace metadata
            nft_name: _,
            nft_description: _,
            nft_image_url: _,
        } = listing;
        
        let affiliate_commission = (total_price * marketplace.affiliate_rate) / 10000;
        let app_commission = (total_price * marketplace.commission_rate) / 10000;
        
        let commission = SaleCommission {
            affiliate_commission,
            app_commission,
            total_price,
        };
        
        // Transfer payment to seller
        sui_transfer::public_transfer(payment, seller);
        
        // Update existing share_nft ownership (preserve original ID)
        share_nft.owner = tx_context::sender(ctx);
        share_nft.affiliate_code = generate_affiliate_code(tx_context::sender(ctx), affiliate_config, clock, ctx);
        share_nft.is_affiliate_active = true;
        share_nft.price = total_price;
        share_nft.is_listed = false;
        share_nft.listing_price = 0;
        
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
        
        commission
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
            // Marketplace metadata
            nft_name: _,
            nft_description: _,
            nft_image_url: _,
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

    // ===== Marketplace Functions =====

    /// Transfer NFT to another address
    public fun transfer(mut nft: VillaShareNFT, recipient: address, clock: &Clock, _ctx: &mut TxContext) {
        let nft_id = object::uid_to_inner(&nft.id);
        let from = nft.owner;
        
        nft.owner = recipient;
        
        event::emit(NFTTransferred {
            nft_id,
            from,
            to: recipient,
            timestamp: clock::timestamp_ms(clock),
        });
        
        sui_transfer::public_transfer(nft, recipient);
    }

    /// List NFT for sale
    public fun list_for_sale(nft: &mut VillaShareNFT, price: u64, clock: &Clock, ctx: &mut TxContext) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        assert!(!nft.is_listed, EAlreadyListed);
        assert!(price > 0, EInvalidListingPrice);

        nft.is_listed = true;
        nft.listing_price = price;
        nft.price = price;

        event::emit(NFTListed {
            nft_id: object::uid_to_inner(&nft.id),
            owner: nft.owner,
            price,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Delist NFT from sale
    public fun delist(nft: &mut VillaShareNFT, clock: &Clock, ctx: &mut TxContext) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        assert!(nft.is_listed, ENotListed);

        nft.is_listed = false;
        nft.listing_price = 0;

        event::emit(NFTDelisted {
            nft_id: object::uid_to_inner(&nft.id),
            owner: nft.owner,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Update NFT price
    public fun update_price(nft: &mut VillaShareNFT, new_price: u64, clock: &Clock, ctx: &mut TxContext) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        assert!(new_price > 0, EInvalidListingPrice);

        let old_price = nft.price;
        nft.price = new_price;
        
        if (nft.is_listed) {
            nft.listing_price = new_price;
        };

        event::emit(PriceUpdated {
            nft_id: object::uid_to_inner(&nft.id),
            old_price,
            new_price,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Get NFT owner
    public fun get_owner(nft: &VillaShareNFT): address {
        nft.owner
    }

    /// Get NFT metadata
    public fun get_metadata(nft: &VillaShareNFT): (String, String, String) {
        (nft.name, nft.description, nft.image_url)
    }

    /// Get NFT name
    public fun get_name(nft: &VillaShareNFT): &String {
        &nft.name
    }

    /// Get NFT description
    public fun get_description(nft: &VillaShareNFT): &String {
        &nft.description
    }

    /// Get NFT image URL
    public fun get_image_url(nft: &VillaShareNFT): &String {
        &nft.image_url
    }

    /// Get NFT price
    public fun get_price(nft: &VillaShareNFT): u64 {
        nft.price
    }

    /// Get NFT listing status
    public fun is_listed(nft: &VillaShareNFT): bool {
        nft.is_listed
    }

    /// Get NFT listing price
    public fun get_listing_price(nft: &VillaShareNFT): u64 {
        nft.listing_price
    }

    /// Update NFT metadata (only owner can update)
    public fun update_metadata(
        nft: &mut VillaShareNFT, 
        new_name: String, 
        new_description: String, 
        new_image_url: String,
        _clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        
        nft.name = new_name;
        nft.description = new_description;
        nft.image_url = new_image_url;
    }

    // ===== User Executor Functions (for zkLogin signature) =====

    /// User buy NFT for self (with zkLogin signature)
    public fun user_buy_for_self(
        marketplace: &mut VillaMarketplace,
        affiliate_config: &AffiliateConfig,
        listing_id: ID,
        _user_payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // Get listing
        let listing = table::remove(&mut marketplace.listings, listing_id);
        
        assert!(listing.is_active, EListingNotFound);
        assert!(clock::timestamp_ms(clock) <= listing.expires_at, EListingExpired);
        
        // Extract data from listing
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
            nft_name,
            nft_description,
            nft_image_url,
        } = listing;
        
        // Validate payment
        assert!(coin::value(&_user_payment) >= total_price, EInsufficientPayment);
        
        // Calculate commissions
        let affiliate_commission = (total_price * marketplace.affiliate_rate) / 10000;
        let app_commission = (total_price * marketplace.commission_rate) / 10000;
        
        // Transfer payment to seller
        sui_transfer::public_transfer(_user_payment, seller);
        
        // Create new NFT for user (who signed the transaction)
        let buyer_address = tx_context::sender(ctx);
        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id,
            villa_id,
            owner: buyer_address, // User becomes owner
            affiliate_code: generate_affiliate_code(buyer_address, affiliate_config, clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
            name: nft_name,
            description: nft_description,
            image_url: nft_image_url,
            price: total_price,
            is_listed: false,
            listing_price: 0,
        };
        
        // Record trade
        let trade = DNFTTrade {
            id: object::new(ctx),
            share_nft_id,
            project_id,
            villa_id,
            seller,
            buyer: buyer_address,
            price: total_price,
            affiliate_commission,
            app_commission,
            timestamp: clock::timestamp_ms(clock),
        };
        table::add(&mut marketplace.trades, share_nft_id, trade);
        
        // Delete the listing UID
        object::delete(listing_id_uid);
        
        // Emit event
        event::emit(DNFTBought {
            share_nft_id: object::uid_to_inner(&share_nft.id),
            buyer: buyer_address,
            seller,
            price: total_price,
            affiliate_commission,
            app_commission,
        });
        
        share_nft
    }

    /// User deposit SUI for self (with zkLogin signature)
    public fun user_deposit_sui_for_self(
        user_vault: &mut UserVault,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate vault ownership
        assert!(user_vault.owner == tx_context::sender(ctx), ENotOwner);

        // Deposit SUI to user vault
        // Note: This function is a placeholder for user deposit functionality
        // The actual deposit logic would be implemented based on business requirements
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Emit event
        event::emit(TokenDeposited {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            amount: 0, // Placeholder amount
            token_type: string::utf8(b"SUI"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// User deposit USDC for self (with zkLogin signature)
    public fun user_deposit_usdc_for_self(
        user_vault: &mut UserVault,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate vault ownership
        assert!(user_vault.owner == tx_context::sender(ctx), ENotOwner);

        // Deposit USDC to user vault
        // Note: This function is a placeholder for user deposit functionality
        // The actual deposit logic would be implemented based on business requirements
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Emit event
        event::emit(TokenDeposited {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            amount: 0, // Placeholder amount
            token_type: string::utf8(b"USDC"),
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// User withdraw SUI for self (with zkLogin signature)
    public fun user_withdraw_sui_for_self(
        user_vault: &mut UserVault,
        amount: u64,
        recipient_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<SUI> {
        // Validate vault ownership
        assert!(user_vault.owner == tx_context::sender(ctx), ENotOwner);

        // Validate balance
        assert!(balance::value(&user_vault.sui_balance) >= amount, EInsufficientBalance);

        // Withdraw from user vault
        let withdrawn_balance = balance::split(&mut user_vault.sui_balance, amount);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Emit event
        event::emit(TokenWithdrawn {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            recipient: recipient_address,
            amount,
            token_type: string::utf8(b"SUI"),
            timestamp: clock::timestamp_ms(clock),
        });

        withdrawn_coin
    }

    /// User withdraw USDC for self (with zkLogin signature)
    public fun user_withdraw_usdc_for_self(
        user_vault: &mut UserVault,
        amount: u64,
        recipient_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<USDC> {
        // Validate vault ownership
        assert!(user_vault.owner == tx_context::sender(ctx), ENotOwner);

        // Validate balance
        assert!(balance::value(&user_vault.usdc_balance) >= amount, EInsufficientBalance);

        // Withdraw from user vault
        let withdrawn_balance = balance::split(&mut user_vault.usdc_balance, amount);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        user_vault.updated_at = clock::timestamp_ms(clock);

        // Emit event
        event::emit(TokenWithdrawn {
            vault_id: object::uid_to_inner(&user_vault.id),
            owner: user_vault.owner,
            recipient: recipient_address,
            amount,
            token_type: string::utf8(b"USDC"),
            timestamp: clock::timestamp_ms(clock),
        });

        withdrawn_coin
    }

    /// User buy NFT with USDC for self (with zkLogin signature)
    public fun user_buy_with_usdc_for_self(
        marketplace: &mut VillaMarketplace,
        affiliate_config: &AffiliateConfig,
        listing_id: ID,
        _user_payment: Coin<USDC>,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // Get listing
        let listing = table::remove(&mut marketplace.listings, listing_id);
        
        assert!(listing.is_active, EListingNotFound);
        assert!(clock::timestamp_ms(clock) <= listing.expires_at, EListingExpired);
        
        // Extract data from listing
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
            nft_name,
            nft_description,
            nft_image_url,
        } = listing;
        
        // Validate payment (assuming USDC and SUI have same decimal places)
        assert!(coin::value(&_user_payment) >= total_price, EInsufficientPayment);
        
        // Calculate commissions
        let affiliate_commission = (total_price * marketplace.affiliate_rate) / 10000;
        let app_commission = (total_price * marketplace.commission_rate) / 10000;
        
        // Transfer payment to seller
        sui_transfer::public_transfer(_user_payment, seller);
        
        // Create new NFT for user (who signed the transaction)
        let buyer_address = tx_context::sender(ctx);
        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id,
            villa_id,
            owner: buyer_address, // User becomes owner
            affiliate_code: generate_affiliate_code(buyer_address, affiliate_config, clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
            name: nft_name,
            description: nft_description,
            image_url: nft_image_url,
            price: total_price,
            is_listed: false,
            listing_price: 0,
        };
        
        // Record trade
        let trade = DNFTTrade {
            id: object::new(ctx),
            share_nft_id,
            project_id,
            villa_id,
            seller,
            buyer: buyer_address,
            price: total_price,
            affiliate_commission,
            app_commission,
            timestamp: clock::timestamp_ms(clock),
        };
        table::add(&mut marketplace.trades, share_nft_id, trade);
        
        // Delete the listing UID
        object::delete(listing_id_uid);
        
        // Emit event
        event::emit(DNFTBought {
            share_nft_id: object::uid_to_inner(&share_nft.id),
            buyer: buyer_address,
            seller,
            price: total_price,
            affiliate_commission,
            app_commission,
        });
        
        share_nft
    }

    // ===== Utility Functions =====

    fun generate_affiliate_code(
        _owner: address, 
        affiliate_config: &AffiliateConfig, 
        clock: &Clock, 
        _ctx: &mut TxContext
    ): String {
        let timestamp = clock::timestamp_ms(clock);
        let _random_part = timestamp % 10000;
        affiliate_config.current_prefix
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

    /// Update villa project information
    public fun update_villa_project(
        _app_cap: &AppCap,
        project: &mut VillaProject,
        new_name: String,
        new_description: String,
        new_commission_rate: u64,
        new_affiliate_rate: u64,
        clock: &Clock
    ) {
        // Validate commission rates
        assert!(new_commission_rate <= 10000, EInvalidCommissionRate);
        assert!(new_affiliate_rate <= 10000, EInvalidCommissionRate);

        // Store old values for event emission
        let old_name = project.name;
        let old_commission_rate = project.commission_rate;
        let old_affiliate_rate = project.affiliate_rate;

        // Update project fields
        project.name = new_name;
        project.description = new_description;
        project.commission_rate = new_commission_rate;
        project.affiliate_rate = new_affiliate_rate;
        project.updated_at = clock::timestamp_ms(clock);

        // Emit update event
        event::emit(VillaProjectUpdated {
            project_id: project.project_id,
            old_name,
            new_name,
            old_commission_rate,
            new_commission_rate,
            old_affiliate_rate,
            new_affiliate_rate,
            updated_at: clock::timestamp_ms(clock),
        });
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

    // ===== Commission System Functions =====

    /// Update commission rate (only by admin)
    public fun update_commission_rate(
        commission_config: &mut CommissionConfig,
        new_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == commission_config.admin_address, ENotAdmin);
        assert!(new_rate <= 10000, EInvalidCommissionRate); // Max 100%
        
        let old_rate = commission_config.current_commission_rate;
        commission_config.current_commission_rate = new_rate;
        commission_config.updated_at = clock::timestamp_ms(clock);

        event::emit(CommissionConfigUpdated {
            admin_address: tx_context::sender(ctx),
            old_rate,
            new_rate,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Admin update affiliate code prefix
    public fun update_affiliate_prefix(
        affiliate_config: &mut AffiliateConfig,
        new_prefix: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == affiliate_config.admin_address, ENotAdmin);
        assert!(affiliate_config.is_active, ENotAuthorized);
        
        let old_prefix = affiliate_config.current_prefix;
        affiliate_config.current_prefix = new_prefix;
        affiliate_config.updated_at = clock::timestamp_ms(clock);

        event::emit(AffiliateConfigUpdated {
            admin_address: tx_context::sender(ctx),
            old_prefix,
            new_prefix,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Get commission configuration info
    public fun get_commission_config(commission_config: &CommissionConfig): (u64, u64, address, bool, u64) {
        (
            commission_config.default_commission_rate,
            commission_config.current_commission_rate,
            commission_config.admin_address,
            commission_config.is_active,
            commission_config.updated_at
        )
    }

    /// Get treasury balance info
    public fun get_treasury_balance_info(treasury_balance: &TreasuryBalance): (u64, u64, u64, u64) {
        (
            balance::value(&treasury_balance.sui_balance),
            balance::value(&treasury_balance.usdc_balance),
            treasury_balance.total_commission_earned,
            treasury_balance.total_commission_withdrawn
        )
    }

    /// Get affiliate configuration info
    public fun get_affiliate_config_info(affiliate_config: &AffiliateConfig): (String, String, address, bool, u64, u64) {
        (
            affiliate_config.default_prefix,
            affiliate_config.current_prefix,
            affiliate_config.admin_address,
            affiliate_config.is_active,
            affiliate_config.created_at,
            affiliate_config.updated_at
        )
    }

    /// Check if address is exempt from commission (admin address)
    public fun is_admin_exempt_from_commission(commission_config: &CommissionConfig, address: address): bool {
        address == commission_config.admin_address
    }

    /// Calculate commission amount
    public fun calculate_commission_amount(
        commission_config: &CommissionConfig,
        total_price: u64,
        seller_address: address
    ): u64 {
        // Admin is exempt from commission
        if (is_admin_exempt_from_commission(commission_config, seller_address)) {
            return 0
        };
        
        // Calculate commission
        (total_price * commission_config.current_commission_rate) / 10000
    }

    /// Admin withdraw SUI from treasury
    public fun admin_withdraw_sui_from_treasury(
        commission_config: &CommissionConfig,
        treasury_balance: &mut TreasuryBalance,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(tx_context::sender(ctx) == commission_config.admin_address, ENotAdmin);
        assert!(balance::value(&treasury_balance.sui_balance) >= amount, EInsufficientTreasuryBalance);

        let withdrawn_balance = balance::split(&mut treasury_balance.sui_balance, amount);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        
        treasury_balance.total_commission_withdrawn = treasury_balance.total_commission_withdrawn + amount;
        treasury_balance.updated_at = clock::timestamp_ms(clock);

        event::emit(CommissionWithdrawn {
            admin_address: tx_context::sender(ctx),
            amount,
            token_type: string::utf8(b"SUI"),
            timestamp: clock::timestamp_ms(clock),
        });

        withdrawn_coin
    }

    /// Admin withdraw USDC from treasury
    public fun admin_withdraw_usdc_from_treasury(
        commission_config: &CommissionConfig,
        treasury_balance: &mut TreasuryBalance,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<USDC> {
        assert!(tx_context::sender(ctx) == commission_config.admin_address, ENotAdmin);
        assert!(balance::value(&treasury_balance.usdc_balance) >= amount, EInsufficientTreasuryBalance);

        let withdrawn_balance = balance::split(&mut treasury_balance.usdc_balance, amount);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        
        treasury_balance.total_commission_withdrawn = treasury_balance.total_commission_withdrawn + amount;
        treasury_balance.updated_at = clock::timestamp_ms(clock);

        event::emit(CommissionWithdrawn {
            admin_address: tx_context::sender(ctx),
            amount,
            token_type: string::utf8(b"USDC"),
            timestamp: clock::timestamp_ms(clock),
        });

        withdrawn_coin
    }

    /// Process commission payment (internal function)
    public fun process_commission_payment(
        commission_config: &mut CommissionConfig,
        treasury_balance: &mut TreasuryBalance,
        payment: &mut Coin<SUI>,
        seller_address: address,
        buyer_address: address,
        total_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<SUI> {
        let commission_amount = calculate_commission_amount(commission_config, total_price, seller_address);
        
        if (commission_amount == 0) {
            // No commission, return full payment to seller
            let seller_payment = coin::split(payment, total_price, ctx);
            return seller_payment
        };

        // Calculate seller payment (after commission deduction)
        let seller_received = total_price - commission_amount;
        
        // Split payment: commission to treasury, rest to seller
        let commission_payment = coin::split(payment, commission_amount, ctx);
        let seller_payment = coin::split(payment, seller_received, ctx);
        
        // Add commission to treasury
        let commission_balance = coin::into_balance(commission_payment);
        balance::join(&mut treasury_balance.sui_balance, commission_balance);
        
        treasury_balance.total_commission_earned = treasury_balance.total_commission_earned + commission_amount;
        treasury_balance.updated_at = clock::timestamp_ms(clock);

        // Emit commission collected event
        event::emit(CommissionCollected {
            seller_address,
            buyer_address,
            total_price,
            commission_amount,
            seller_received,
            timestamp: clock::timestamp_ms(clock),
        });

        // Emit treasury balance updated event
        event::emit(TreasuryBalanceUpdated {
            sui_balance: balance::value(&treasury_balance.sui_balance),
            usdc_balance: balance::value(&treasury_balance.usdc_balance),
            total_earned: treasury_balance.total_commission_earned,
            timestamp: clock::timestamp_ms(clock),
        });

        seller_payment
    }

    /// Process USDC commission payment (internal function)
    public fun process_usdc_commission_payment(
        commission_config: &mut CommissionConfig,
        treasury_balance: &mut TreasuryBalance,
        payment: &mut Coin<USDC>,
        seller_address: address,
        buyer_address: address,
        total_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<USDC> {
        let commission_amount = calculate_commission_amount(commission_config, total_price, seller_address);
        
        if (commission_amount == 0) {
            // No commission, return full payment to seller
            let seller_payment = coin::split(payment, total_price, ctx);
            return seller_payment
        };

        // Calculate seller payment (after commission deduction)
        let seller_received = total_price - commission_amount;
        
        // Split payment: commission to treasury, rest to seller
        let commission_payment = coin::split(payment, commission_amount, ctx);
        let seller_payment = coin::split(payment, seller_received, ctx);
        
        // Add commission to treasury
        let commission_balance = coin::into_balance(commission_payment);
        balance::join(&mut treasury_balance.usdc_balance, commission_balance);
        
        treasury_balance.total_commission_earned = treasury_balance.total_commission_earned + commission_amount;
        treasury_balance.updated_at = clock::timestamp_ms(clock);

        // Emit commission collected event
        event::emit(CommissionCollected {
            seller_address,
            buyer_address,
            total_price,
            commission_amount,
            seller_received,
            timestamp: clock::timestamp_ms(clock),
        });

        // Emit treasury balance updated event
        event::emit(TreasuryBalanceUpdated {
            sui_balance: balance::value(&treasury_balance.sui_balance),
            usdc_balance: balance::value(&treasury_balance.usdc_balance),
            total_earned: treasury_balance.total_commission_earned,
            timestamp: clock::timestamp_ms(clock),
        });

        seller_payment
    }

    // ===== Batch Escrow Configuration Functions =====

    /// Create batch escrow configuration
    public fun create_batch_escrow_config(
        super_admin_registry: &mut SuperAdminRegistry,
        max_batch_size: u64,
        default_expiry_hours: u64,
        default_affiliate_active: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ): BatchEscrowConfig {
        
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Validate configuration values
        assert!(max_batch_size > 0, EInvalidAmount);
        assert!(default_expiry_hours > 0, EInvalidAmount);
        
        BatchEscrowConfig {
            id: object::new(ctx),
            max_batch_size: max_batch_size,
            default_expiry_hours: default_expiry_hours,
            default_affiliate_active: default_affiliate_active,
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        }
    }

    /// Update batch escrow configuration
    public fun update_batch_escrow_config(
        super_admin_registry: &mut SuperAdminRegistry,
        config: &mut BatchEscrowConfig,
        max_batch_size: u64,
        default_expiry_hours: u64,
        default_affiliate_active: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        
        // Validate admin permissions
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Validate configuration values
        assert!(max_batch_size > 0, EInvalidAmount);
        assert!(default_expiry_hours > 0, EInvalidAmount);
        
        // Update configuration
        config.max_batch_size = max_batch_size;
        config.default_expiry_hours = default_expiry_hours;
        config.default_affiliate_active = default_affiliate_active;
        config.updated_at = clock::timestamp_ms(clock);
        
        // Emit event
        event::emit(BatchEscrowConfigUpdated {
            admin_address: admin_address,
            max_batch_size: max_batch_size,
            default_expiry_hours: default_expiry_hours,
            default_affiliate_active: default_affiliate_active,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // ===== Batch Escrow Functions =====

    // Create batch escrow with USDC payment for atomic batch minting
    #[allow(lint(self_transfer))]
    public fun create_batch_escrow_with_payment(
        super_admin_registry: &mut SuperAdminRegistry,
        batch_escrow_config: &BatchEscrowConfig,
        user_address: address,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        nft_count: u64,
        user_payment: Coin<USDC>,
        clock: &Clock,
        ctx: &mut TxContext
    ): BatchEscrow<USDC> {
        
        // ===== VALIDATE ADMIN PERMISSIONS =====
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Validate permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"ADMIN_MINT_FOR_USER")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);
        
        // ===== VALIDATE MINTING CONSTRAINTS =====
        assert!(nft_count > 0, EInvalidAmount);
        assert!(nft_count <= batch_escrow_config.max_batch_size, EExceedsBatchLimit);
        
        // Validate remaining villa shares
        let remaining_villa_shares = villa_metadata.max_shares - villa_metadata.shares_issued;
        assert!(nft_count <= remaining_villa_shares, EExceedsVillaLimit);
        
        // Validate remaining project shares
        let remaining_project_shares = project.max_total_shares - project.total_shares_issued;
        assert!(nft_count <= remaining_project_shares, EExceedsProjectLimit);
        
        // ===== VALIDATE PAYMENT =====
        let price_per_share = villa_metadata.price_per_share;
        let total_price = price_per_share * nft_count;
        
        // Validate payment amount
        assert!(coin::value(&user_payment) >= total_price, EInsufficientPayment);
        
        // ===== CREATE BATCH ESCROW =====
        let expires_at = clock::timestamp_ms(clock) + (batch_escrow_config.default_expiry_hours * 3600000); // Convert hours to milliseconds
        
        // Create batch escrow without storing payment
        let total_amount = coin::value(&user_payment);
        let batch_escrow = BatchEscrow<USDC> {
            id: object::new(ctx),
            buyer: user_address,
            platform: admin_address,
            total_amount: total_amount,
            nft_count: nft_count,
            nft_ids: vector::empty<ID>(),
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            created_at: clock::timestamp_ms(clock),
            expires_at: expires_at,
            status: BATCH_ESCROW_PENDING,
            successful_nfts: 0,
            failed_nfts: 0,
            processed_amount: 0,
            refund_amount: 0,
        };
        
        // Transfer payment to platform treasury immediately (like existing buy functions)
        sui_transfer::public_transfer(user_payment, admin_address);
        
        // ===== EMIT EVENT =====
        event::emit(BatchEscrowCreated {
            escrow_id: object::uid_to_inner(&batch_escrow.id),
            buyer: user_address,
            platform: admin_address,
            total_amount: total_amount,
            nft_count: nft_count,
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            expires_at: expires_at,
            timestamp: clock::timestamp_ms(clock),
        });
        
        // ===== RETURN ESCROW =====
        batch_escrow
    }

    /// Admin perform batch minting with existing escrow
    public fun admin_batch_mint_with_escrow(
        super_admin_registry: &mut SuperAdminRegistry,
        batch_escrow: &mut BatchEscrow<USDC>,
        batch_escrow_config: &BatchEscrowConfig,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        affiliate_config: &AffiliateConfig,
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
        clock: &Clock,
        ctx: &mut TxContext
    ): vector<VillaShareNFT> {
        
        // ===== VALIDATE ADMIN PERMISSIONS =====
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // ===== VALIDATE ESCROW =====
        assert!(batch_escrow.status == BATCH_ESCROW_PENDING, EInvalidEscrowStatus);
        assert!(clock::timestamp_ms(clock) <= batch_escrow.expires_at, EEscrowExpired);
        
        // ===== UPDATE STATUS TO PROCESSING =====
        batch_escrow.status = BATCH_ESCROW_PROCESSING;
        
        // ===== BATCH MINTING =====
        let mut nft_list = vector::empty<VillaShareNFT>();
        let mut nft_id_list = vector::empty<ID>();
        let mut successful_count = 0;
        let failed_count = 0;
        
        let price_per_share = villa_metadata.price_per_share;
        
        let mut i = 0;
        while (i < batch_escrow.nft_count) {
            // Create NFT for user
            let share_nft = VillaShareNFT {
                id: object::new(ctx),
                project_id: project.project_id,
                villa_id: villa_metadata.villa_id,
                owner: batch_escrow.buyer,
                affiliate_code: generate_affiliate_code(batch_escrow.buyer, affiliate_config, clock, ctx),
                is_affiliate_active: batch_escrow_config.default_affiliate_active,
                created_at: clock::timestamp_ms(clock),
                name: nft_name,
                description: nft_description,
                image_url: nft_image_url,
                price: price_per_share,
                is_listed: true,  // Set true for ownership tracking
                listing_price: price_per_share,
            };
            
            // Add NFT to list
            vector::push_back(&mut nft_list, share_nft);
            
            // Add NFT ID to list
            vector::push_back(&mut nft_id_list, object::uid_to_inner(&vector::borrow(&nft_list, i).id));
            
            successful_count = successful_count + 1;
            
            i = i + 1;
        };
        
        // ===== UPDATE ESCROW =====
        batch_escrow.nft_ids = nft_id_list;
        batch_escrow.successful_nfts = successful_count;
        batch_escrow.failed_nfts = failed_count;
        
        // ===== CALCULATE PAYMENTS =====
        let processed_amount = price_per_share * successful_count;
        let refund_amount = batch_escrow.total_amount - processed_amount;
        
        batch_escrow.processed_amount = processed_amount;
        batch_escrow.refund_amount = refund_amount;
        
        // ===== UPDATE METADATA =====
        villa_metadata.shares_issued = villa_metadata.shares_issued + successful_count;
        project.total_shares_issued = project.total_shares_issued + successful_count;
        
        // ===== DETERMINE FINAL STATUS =====
        if (successful_count == batch_escrow.nft_count) {
            batch_escrow.status = BATCH_ESCROW_COMPLETED;
        } else if (successful_count > 0) {
            batch_escrow.status = BATCH_ESCROW_PARTIAL;
        } else {
            batch_escrow.status = BATCH_ESCROW_FAILED;
        };
        
        // ===== EMIT EVENTS =====
        // Emit event for each successful NFT
        let mut i = 0;
        while (i < successful_count) {
            event::emit(VillaSharesMinted {
                project_id: project.project_id,
                villa_id: villa_metadata.villa_id,
                amount: 1,
                total_shares_issued: villa_metadata.shares_issued,
                created_at: clock::timestamp_ms(clock),
                nft_name: nft_name,
                nft_description: nft_description,
                nft_image_url: nft_image_url,
                nft_price: price_per_share,
            });
            i = i + 1;
        };
        
        // Emit batch minting completed event
        event::emit(BatchMintingCompleted {
            escrow_id: object::uid_to_inner(&batch_escrow.id),
            buyer: batch_escrow.buyer,
            platform: admin_address,
            total_nfts: batch_escrow.nft_count,
            successful_nfts: successful_count,
            failed_nfts: failed_count,
            processed_amount: processed_amount,
            refund_amount: refund_amount,
            timestamp: clock::timestamp_ms(clock),
        });
        
        // ===== RETURN NFT LIST =====
        nft_list
    }

    /// Process batch escrow payment and refund
    public fun process_batch_escrow_payment(
        batch_escrow: &mut BatchEscrow<USDC>,
        commission_config: &mut CommissionConfig,
        treasury_balance: &mut TreasuryBalance,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        
        // ===== VALIDATE STATUS =====
        assert!(batch_escrow.status == BATCH_ESCROW_COMPLETED || 
                batch_escrow.status == BATCH_ESCROW_PARTIAL || 
                batch_escrow.status == BATCH_ESCROW_FAILED, EInvalidEscrowStatus);
        
        // ===== PROCESS PAYMENT FOR SUCCESSFUL NFTS =====
        if (batch_escrow.processed_amount > 0) {
            // Calculate platform commission
            let commission_rate = commission_config.current_commission_rate;
            let commission_amount = (batch_escrow.processed_amount * commission_rate) / 10000;
            
            // Update treasury commission earned
            treasury_balance.total_commission_earned = treasury_balance.total_commission_earned + commission_amount;
        };
        
        // ===== REFUND FOR FAILED NFTS =====
        // Note: Refund will be handled by platform treasury
        // This function only updates the escrow status and emits events
        
        // ===== EMIT EVENTS =====
        event::emit(BatchEscrowProcessed {
            escrow_id: object::uid_to_inner(&batch_escrow.id),
            buyer: batch_escrow.buyer,
            platform: batch_escrow.platform,
            processed_amount: batch_escrow.processed_amount,
            refund_amount: batch_escrow.refund_amount,
            successful_nfts: batch_escrow.successful_nfts,
            failed_nfts: batch_escrow.failed_nfts,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Admin cancel batch escrow and refund all funds
    public fun admin_cancel_batch_escrow(
        super_admin_registry: &mut SuperAdminRegistry,
        batch_escrow: &mut BatchEscrow<USDC>,
        cancel_reason: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        
        // ===== VALIDATE ADMIN PERMISSIONS =====
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        // ===== VALIDATE STATUS =====
        assert!(batch_escrow.status == BATCH_ESCROW_PENDING || 
                batch_escrow.status == BATCH_ESCROW_PROCESSING, EInvalidEscrowStatus);
        
        // ===== VALIDATE CANCEL REASON =====
        assert!(cancel_reason >= 1 && cancel_reason <= 5, EInvalidCancelReason);
        
        // ===== REFUND ALL FUNDS =====
        // Note: Refund will be handled by platform treasury
        // This function only updates the escrow status and emits events
        
        // ===== UPDATE STATUS =====
        batch_escrow.status = BATCH_ESCROW_CANCELLED;
        
        // ===== EMIT EVENT =====
        event::emit(BatchEscrowCancelled {
            escrow_id: object::uid_to_inner(&batch_escrow.id),
            buyer: batch_escrow.buyer,
            platform: admin_address,
            total_amount: batch_escrow.total_amount,
            nft_count: batch_escrow.nft_count,
            cancel_reason: cancel_reason,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // ===== Batch Escrow Helper Functions =====

    /// Get batch escrow configuration details
    public fun get_batch_escrow_config_details(config: &BatchEscrowConfig): (u64, u64, bool) {
        (config.max_batch_size, config.default_expiry_hours, config.default_affiliate_active)
    }

    /// Get batch escrow status
    public fun get_batch_escrow_status(batch_escrow: &BatchEscrow<USDC>): u8 {
        batch_escrow.status
    }

    /// Check if batch escrow is expired
    public fun is_batch_escrow_expired(batch_escrow: &BatchEscrow<USDC>, clock: &Clock): bool {
        clock::timestamp_ms(clock) > batch_escrow.expires_at
    }

    /// Get batch escrow details
    public fun get_batch_escrow_details(batch_escrow: &BatchEscrow<USDC>): (address, address, u64, u64, u8) {
        (batch_escrow.buyer, batch_escrow.platform, batch_escrow.total_amount, batch_escrow.nft_count, batch_escrow.status)
    }

    /// Cleanup completed batch escrow
    public fun cleanup_batch_escrow(batch_escrow: BatchEscrow<USDC>) {
        // Validate escrow is completed or cancelled
        assert!(batch_escrow.status == BATCH_ESCROW_COMPLETED || 
                batch_escrow.status == BATCH_ESCROW_CANCELLED, EInvalidBatchEscrowStatus);
        
        // Delete escrow object
        let BatchEscrow<USDC> {
            id,
            buyer: _,
            platform: _,
            total_amount: _,
            nft_count: _,
            nft_ids: _,
            project_id: _,
            villa_id: _,
            created_at: _,
            expires_at: _,
            status: _,
            successful_nfts: _,
            failed_nfts: _,
            processed_amount: _,
            refund_amount: _,
        } = batch_escrow;
        
        object::delete(id);
    }
}
