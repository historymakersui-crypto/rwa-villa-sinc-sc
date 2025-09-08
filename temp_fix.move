    public fun buy_dnft_from_marketplace(
        marketplace: &mut VillaMarketplace,
        listing_id: ID,
        payment: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (VillaShareNFT, SaleCommission) {
        // Get listing from marketplace
        let listing = table::remove(&mut marketplace.listings, listing_id);
        
        // Validate listing
        assert!(listing.is_active, EListingNotFound);
        assert!(clock::timestamp_ms(clock) <= listing.expires_at, EListingExpired);
        
        // Calculate commission
        let total_price = listing.price;
        let affiliate_commission = (total_price * marketplace.affiliate_rate) / 10000;
        let app_commission = (total_price * marketplace.commission_rate) / 10000;
        
        // Create commission struct
        let commission = SaleCommission {
            affiliate_commission,
            app_commission,
            total_price,
        };
        
        // Transfer payment to seller
        let seller_payment = total_price - affiliate_commission - app_commission;
        transfer::public_transfer(payment, listing.seller);
        
        // Create new VillaShareNFT
        let share_nft = VillaShareNFT {
            id: object::new(ctx),
            project_id: listing.project_id,
            villa_id: listing.villa_id,
            owner: tx_context::sender(ctx),
            affiliate_code: generate_affiliate_code(tx_context::sender(ctx), clock, ctx),
            is_affiliate_active: true,
            created_at: clock::timestamp_ms(clock),
        };
        
        // Emit event
        event::emit(DNFTBought {
            share_nft_id: object::uid_to_inner(&share_nft.id),
            buyer: tx_context::sender(ctx),
            seller: listing.seller,
            price: total_price,
            affiliate_commission,
            app_commission,
        });
        
        (share_nft, commission)
    }
