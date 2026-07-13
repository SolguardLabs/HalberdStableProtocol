# pragma version ^0.4.3

event AuctionStarted:
    auction_id: indexed(uint256)
    vault_id: indexed(uint256)
    asset: indexed(address)
    collateral_amount: uint256
    debt_target: uint256

event BidPlaced:
    auction_id: indexed(uint256)
    bidder: indexed(address)
    bid_amount: uint256
    collateral_claim: uint256

event AuctionClosed:
    auction_id: indexed(uint256)
    winner: indexed(address)
    bid_amount: uint256
    collateral_claim: uint256

event AuctionCanceled:
    auction_id: indexed(uint256)

struct Auction:
    vault_id: uint256
    asset: address
    seller: address
    collateral_amount: uint256
    debt_target: uint256
    start_time: uint256
    end_time: uint256
    best_bidder: address
    best_bid: uint256
    collateral_claim: uint256
    closed: bool
    canceled: bool

BPS: constant(uint256) = 10_000

admin: public(address)
module: public(address)
next_auction_id: public(uint256)
min_bid_increment_bps: public(uint256)
default_duration: public(uint256)
auctions: public(HashMap[uint256, Auction])
active_by_vault: public(HashMap[uint256, uint256])
bid_count: public(HashMap[uint256, uint256])
bidder_volume: public(HashMap[address, uint256])

@deploy
def __init__(_admin: address):
    assert _admin != empty(address), "admin"
    self.admin = _admin
    self.module = _admin
    self.next_auction_id = 1
    self.min_bid_increment_bps = 500
    self.default_duration = 3_600

@internal
@view
def _only_admin():
    assert msg.sender == self.admin, "admin"

@internal
@view
def _only_module():
    assert msg.sender == self.module or msg.sender == self.admin, "module"

@external
def configure(module: address, min_increment_bps: uint256, duration: uint256):
    self._only_admin()
    assert module != empty(address), "module"
    assert min_increment_bps <= 2_000, "increment"
    assert duration >= 60, "duration"
    self.module = module
    self.min_bid_increment_bps = min_increment_bps
    self.default_duration = duration

@external
def start_auction(vault_id: uint256, asset: address, seller: address, collateral_amount: uint256, debt_target: uint256) -> uint256:
    self._only_module()
    assert vault_id > 0, "vault"
    assert asset != empty(address), "asset"
    assert seller != empty(address), "seller"
    assert collateral_amount > 0, "collateral"
    assert debt_target > 0, "debt"
    assert self.active_by_vault[vault_id] == 0, "active"
    auction_id: uint256 = self.next_auction_id
    self.next_auction_id += 1
    self.auctions[auction_id] = Auction(
        vault_id=vault_id,
        asset=asset,
        seller=seller,
        collateral_amount=collateral_amount,
        debt_target=debt_target,
        start_time=block.timestamp,
        end_time=block.timestamp + self.default_duration,
        best_bidder=empty(address),
        best_bid=0,
        collateral_claim=0,
        closed=False,
        canceled=False,
    )
    self.active_by_vault[vault_id] = auction_id
    log AuctionStarted(
        auction_id=auction_id,
        vault_id=vault_id,
        asset=asset,
        collateral_amount=collateral_amount,
        debt_target=debt_target,
    )
    return auction_id

@external
def bid(auction_id: uint256, bid_amount: uint256, collateral_claim: uint256):
    auction: Auction = self.auctions[auction_id]
    assert auction.asset != empty(address), "auction"
    assert not auction.closed and not auction.canceled, "closed"
    assert block.timestamp <= auction.end_time, "ended"
    assert bid_amount > 0, "bid"
    assert collateral_claim > 0 and collateral_claim <= auction.collateral_amount, "claim"
    if auction.best_bid > 0:
        required: uint256 = auction.best_bid * (BPS + self.min_bid_increment_bps) // BPS
        assert bid_amount >= required, "increment"
    self.auctions[auction_id].best_bidder = msg.sender
    self.auctions[auction_id].best_bid = bid_amount
    self.auctions[auction_id].collateral_claim = collateral_claim
    self.bid_count[auction_id] += 1
    self.bidder_volume[msg.sender] += bid_amount
    log BidPlaced(
        auction_id=auction_id,
        bidder=msg.sender,
        bid_amount=bid_amount,
        collateral_claim=collateral_claim,
    )

@external
def close(auction_id: uint256):
    self._only_module()
    auction: Auction = self.auctions[auction_id]
    assert auction.asset != empty(address), "auction"
    assert not auction.closed and not auction.canceled, "closed"
    assert block.timestamp > auction.end_time or auction.best_bid >= auction.debt_target, "open"
    self.auctions[auction_id].closed = True
    self.active_by_vault[auction.vault_id] = 0
    log AuctionClosed(
        auction_id=auction_id,
        winner=auction.best_bidder,
        bid_amount=auction.best_bid,
        collateral_claim=auction.collateral_claim,
    )

@external
def cancel(auction_id: uint256):
    self._only_module()
    auction: Auction = self.auctions[auction_id]
    assert auction.asset != empty(address), "auction"
    assert not auction.closed and not auction.canceled, "closed"
    self.auctions[auction_id].canceled = True
    self.active_by_vault[auction.vault_id] = 0
    log AuctionCanceled(auction_id=auction_id)

@external
@view
def auction_status(auction_id: uint256) -> (bool, bool, address, uint256, uint256):
    auction: Auction = self.auctions[auction_id]
    return (
        auction.closed,
        auction.canceled,
        auction.best_bidder,
        auction.best_bid,
        auction.collateral_claim,
    )

@external
@view
def discount_bps(auction_id: uint256) -> uint256:
    auction: Auction = self.auctions[auction_id]
    if auction.debt_target == 0 or auction.best_bid == 0:
        return 0
    if auction.best_bid >= auction.debt_target:
        return 0
    return (auction.debt_target - auction.best_bid) * BPS // auction.debt_target

