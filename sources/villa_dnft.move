/// Villa RWA Dynamic NFT Implementation for Sui
/// Final working implementation for Sui Mainnet
module villa_rwa::villa_dnft {
    use sui::transfer as sui_transfer;
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::package;
    use sui::display;
    use std::string::{Self, String};
    use usdc::usdc::USDC;

    // ===== Error Codes =====
    const ENotAuthorized: u64 = 1;
    const EInvalidMaxShares: u64 = 11;
    const EInvalidPrice: u64 = 12;
    const EListingExpired: u64 = 15;
    const EExceedsProjectLimit: u64 = 9;
    const EExceedsVillaLimit: u64 = 10;
    const EInvalidPricePerShare: u64 = 17;
    const EExceedsMaxShares: u64 = 18;
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
    const EInvalidAmount: u64 = 33;
    const ENotOwner: u64 = 34;

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

    /// Treasury Configuration - stores treasury wallet address (owner-updateable)
    #[allow(unused_field)]
    public struct TreasuryConfig has key, store {
        id: UID,
        treasury_address: address,
        admin_address: address,
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

    #[allow(unused_field)]
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

    #[allow(unused_field)]
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

    #[allow(unused_field)]
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
        
        // Create app capability (OWNED — not shared)
        let app_cap = AppCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        // Auditor Fix: Do NOT share capabilities. Transfer ownership to deployer.
        sui_transfer::transfer(app_cap, tx_context::sender(ctx));

        // Create admin capability (OWNED — not shared)
        let admin_cap = AdminCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        // Auditor Fix: Do NOT share capabilities. Transfer ownership to deployer.
        sui_transfer::transfer(admin_cap, tx_context::sender(ctx));

        // Create asset manager capability (OWNED — not shared)
        let asset_manager_cap = AssetManagerCap {
            id: object::new(ctx),
            app_address: tx_context::sender(ctx),
        };
        // Auditor Fix: Do NOT share capabilities. Transfer ownership to deployer.
        sui_transfer::transfer(asset_manager_cap, tx_context::sender(ctx));

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
            string::utf8(b"VILLA_MANAGEMENT")
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

        // Initialize affiliate configuration with default values
        let current_timestamp = 0; // Will be updated when clock is available
        let affiliate_config = AffiliateConfig {
            id: object::new(ctx),
            default_prefix: string::utf8(b"AF"), // Default prefix "AF"
            current_prefix: string::utf8(b"AF"), // Current prefix "AF"
            admin_address: tx_context::sender(ctx),
            is_active: true,
            created_at: current_timestamp,
            updated_at: current_timestamp,
        };

        // Transfer affiliate config to admin
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
        _ctx: &mut TxContext
    ) {
        // Auditor Fix: Disabled. Creating shared capabilities is insecure.
        // This function intentionally aborts to prevent shared AppCap creation.
        assert!(false, EPermissionDenied);
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
        assert!(commission_rate <= 10000, EInvalidAmount);
        assert!(affiliate_rate <= 10000, EInvalidAmount);

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

    /// ═══════════════════════════════════════════════════════════════════════════════════
    /// Admin mint NFT for user WITH PAYMENT + ATOMIC VALIDATION
    /// ═══════════════════════════════════════════════════════════════════════════════════
    /// 
    /// This function performs atomic payment + minting in a single blockchain transaction:
    /// 1. Validates payment amount ≥ expected_amount (fails if insufficient)
    /// 2. Validates admin permission + admin active status
    /// 3. Validates NFT availability (shares_issued < max_shares & project capacity)
    /// 4. Deposits payment to treasury (irreversible state change on success)
    /// 5. Mints NFT to user wallet
    /// 
    /// Guarantees:
    /// - If payment validation fails → Entire TX aborts, NO payment taken, NO minting
    /// - If admin/permission validation fails → Entire TX aborts, NO payment taken, NO minting
    /// - If NFT availability fails → Entire TX aborts, NO payment taken, NO minting
    /// - If all validations pass → Payment deposited AND NFT minted (atomic)
    /// - If minting fails after payment → Entire TX aborts, payment returned (blockchain atomic)
    ///
    public fun admin_mint_for_user(
        super_admin_registry: &mut SuperAdminRegistry,
        user_address: address,
        project: &mut VillaProject,
        villa_metadata: &mut VillaMetadata,
        affiliate_config: &AffiliateConfig,
        treasury_config: &TreasuryConfig,
        payment: Coin<USDC>,
        expected_amount: u64,
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 1: VALIDATE PAYMENT - FAIL FAST (before any state changes)
        // ════════════════════════════════════════════════════════════════════════════════
        let payment_amount = coin::value(&payment);
        assert!(payment_amount >= expected_amount, EInsufficientPayment);

        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 2: VALIDATE ADMIN PERMISSIONS (before any state changes)
        // ════════════════════════════════════════════════════════════════════════════════
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

        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 3: VALIDATE NFT AVAILABILITY (before any state changes)
        // ════════════════════════════════════════════════════════════════════════════════
        assert!(villa_metadata.shares_issued < villa_metadata.max_shares, EExceedsVillaLimit);
        assert!(project.total_shares_issued < project.max_total_shares, EExceedsProjectLimit);

        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 4: IF ALL VALIDATIONS PASS → TRANSFER PAYMENT DIRECTLY TO TREASURY WALLET
        // ════════════════════════════════════════════════════════════════════════════════
        sui_transfer::public_transfer(payment, treasury_config.treasury_address);

        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 5: MINT NFT FOR USER (guaranteed to succeed after step 4 if implementation correct)
        // ════════════════════════════════════════════════════════════════════════════════
        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id: project.project_id,
            villa_id: villa_metadata.villa_id,
            owner: user_address, // User becomes owner (parameter-specified)
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

        // Update counters (after all validations and after minting object created)
        villa_metadata.shares_issued = villa_metadata.shares_issued + 1;
        villa_metadata.updated_at = clock::timestamp_ms(clock);
        project.total_shares_issued = project.total_shares_issued + 1;
        project.updated_at = clock::timestamp_ms(clock);

        // ════════════════════════════════════════════════════════════════════════════════
        // EMIT EVENTS - with payment information
        // ════════════════════════════════════════════════════════════════════════════════
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
        treasury_config: &TreasuryConfig,
        payment: Coin<USDC>,
        expected_amount: u64,
        nft_name: String,
        nft_description: String,
        nft_image_url: String,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaShareNFT {
        // Validate payment first (USDC)
        let payment_amount = coin::value(&payment);
        assert!(payment_amount >= expected_amount, EInsufficientPayment);

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

        // Transfer USDC payment directly to treasury wallet (no storage in struct)
        sui_transfer::public_transfer(payment, treasury_config.treasury_address);

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

        // Emit admin transfer audit event
        event::emit(AdminTransferredForUser {
            nft_id,
            admin_address,
            from_address,
            to_address,
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

        // Emit admin transfer audit event
        event::emit(AdminTransferredForUser {
            nft_id,
            admin_address,
            from_address,
            to_address,
            timestamp: clock::timestamp_ms(clock),
        });
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
        super_admin_registry: &SuperAdminRegistry,
        project_id: String,
        name: String,
        description: String,
        max_total_shares: u64,
        commission_rate: u64,
        affiliate_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): VillaProject {
        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 1: VALIDATE ADMIN PERMISSIONS (before any state changes)
        // ════════════════════════════════════════════════════════════════════════════════
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has PROJECT_MANAGEMENT permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"PROJECT_MANAGEMENT")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 2: VALIDATE PROJECT PARAMETERS
        // ════════════════════════════════════════════════════════════════════════════════
        assert!(max_total_shares > 0, EInvalidMaxShares);
        assert!(commission_rate <= 10000, EInvalidAmount);
        assert!(affiliate_rate <= 10000, EInvalidAmount);

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
        super_admin_registry: &SuperAdminRegistry,
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
        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 1: VALIDATE ADMIN PERMISSIONS (before any state changes)
        // ════════════════════════════════════════════════════════════════════════════════
        let admin_address = tx_context::sender(ctx);
        assert!(table::contains(&super_admin_registry.admins, admin_address), ENotAdmin);
        
        let admin_info = table::borrow(&super_admin_registry.admins, admin_address);
        assert!(admin_info.is_active, ENotAdmin);
        
        // Check if admin has VILLA_MANAGEMENT permission
        let mut has_permission = false;
        let mut i = 0;
        let len = vector::length(&admin_info.permissions);
        while (i < len) {
            if (vector::borrow(&admin_info.permissions, i) == &string::utf8(b"VILLA_MANAGEMENT")) {
                has_permission = true;
                break
            };
            i = i + 1;
        };
        assert!(has_permission, EPermissionDenied);

        // ════════════════════════════════════════════════════════════════════════════════
        // STEP 2: VALIDATE VILLA PARAMETERS
        // ════════════════════════════════════════════════════════════════════════════════
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

    // ═════════════════════════════════════════════════════════════════════════════════════
    // ✅ DEPRECATED & REMOVED FUNCTIONS
    // ═════════════════════════════════════════════════════════════════════════════════════
    // mint_villa_share() - REMOVED (was unused, now replaced by admin_mint_for_user with payment)
    // mint_villa_shares_batch() - REMOVED (was unused, now replaced by admin_mint_for_user with payment)
    // Use admin_mint_for_user() instead for all minting operations (includes payment validation)


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

    public fun create_treasury_config(
        _admin_cap: &AdminCap,
        treasury_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): TreasuryConfig {
        TreasuryConfig {
            id: object::new(ctx),
            treasury_address,
            admin_address: tx_context::sender(ctx),
            created_at: clock::timestamp_ms(clock),
            updated_at: clock::timestamp_ms(clock),
        }
    }

    public fun update_treasury_address(
        _admin_cap: &AdminCap,
        treasury_config: &mut TreasuryConfig,
        new_treasury_address: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(treasury_config.admin_address == tx_context::sender(ctx), ENotAuthorized);
        treasury_config.treasury_address = new_treasury_address;
        treasury_config.updated_at = clock::timestamp_ms(clock);
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

    // ===== NFT utility functions =====

    /// Update NFT price
    public fun update_price(nft: &mut VillaShareNFT, new_price: u64, _clock: &Clock, ctx: &mut TxContext) {
        assert!(nft.owner == tx_context::sender(ctx), ENotOwner);
        assert!(new_price > 0, EInvalidAmount);

        let _old_price = nft.price;
        nft.price = new_price;
        
        if (nft.is_listed) {
            nft.listing_price = new_price;
        };

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

    // ===== Utility Functions =====

    fun generate_affiliate_code(
        _owner: address, 
        _affiliate_config: &AffiliateConfig, 
        _clock: &Clock, 
        _ctx: &mut TxContext
    ): String {
        // On-chain affiliate disabled; return empty string for compatibility
        string::utf8(b"")
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
        assert!(new_commission_rate <= 10000, EInvalidAmount);
        assert!(new_affiliate_rate <= 10000, EInvalidAmount);

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

    public fun get_affiliate_reward_info(affiliate_reward: &AffiliateReward): (String, address, u64, u64, u64) {
        (affiliate_reward.affiliate_code, affiliate_reward.owner, affiliate_reward.total_earned, affiliate_reward.total_paid, affiliate_reward.pending_amount)
    }

    public fun get_app_treasury_info(app_treasury: &AppTreasury): (String, u64, u64, u64) {
        (app_treasury.project_id, app_treasury.total_earned, app_treasury.total_paid, app_treasury.pending_amount)
    }

}
