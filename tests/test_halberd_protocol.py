import pytest

from conftest import WAD, open_vault


def test_vault_minting_and_collateralization(protocol, w3):
    alice = protocol["alice"]
    vaults = protocol["vaults"]
    stable = protocol["stable"]
    collateral = protocol["collateral"]

    vault_id = open_vault(w3, protocol, alice, 10 * WAD, 6_000 * WAD)

    owner, asset, collateral_amount, debt, *_ = vaults.functions.vaults(vault_id).call()
    assert owner == alice
    assert asset == collateral.address
    assert collateral_amount == 10 * WAD
    assert debt == 6_000 * WAD
    assert stable.functions.balanceOf(alice).call() == 6_000 * WAD
    assert vaults.functions.health_bps(vault_id).call() == 16_666


def test_repay_and_withdraw_after_debt_reduction(protocol, w3):
    alice = protocol["alice"]
    vaults = protocol["vaults"]
    stable = protocol["stable"]

    vault_id = open_vault(w3, protocol, alice, 10 * WAD, 5_000 * WAD)
    stable.functions.approve(vaults.address, 2_000 * WAD).transact({"from": alice})
    vaults.functions.repay(vault_id, 2_000 * WAD).transact({"from": alice})
    vaults.functions.withdraw(vault_id, 4 * WAD).transact({"from": alice})

    _, _, collateral_amount, debt, *_ = vaults.functions.vaults(vault_id).call()
    assert collateral_amount == 6 * WAD
    assert debt == 3_000 * WAD
    assert vaults.functions.health_bps(vault_id).call() == 20_000


def test_liquidation_after_oracle_price_drop(protocol, w3):
    alice = protocol["alice"]
    liquidator = protocol["liquidator"]
    vaults = protocol["vaults"]
    stable = protocol["stable"]
    collateral = protocol["collateral"]
    oracle = protocol["oracle"]

    unsafe = open_vault(w3, protocol, alice, 10 * WAD, 6_000 * WAD)
    helper = open_vault(w3, protocol, liquidator, 10 * WAD, 3_000 * WAD)
    assert helper > unsafe

    oracle.functions.push_price(collateral.address, 500 * WAD).transact({"from": protocol["admin"]})
    assert vaults.functions.health_bps(unsafe).call() == 8_333

    before = collateral.functions.balanceOf(liquidator).call()
    stable.functions.approve(vaults.address, 1_000 * WAD).transact({"from": liquidator})
    vaults.functions.liquidate(unsafe, 1_000 * WAD).transact({"from": liquidator})
    after = collateral.functions.balanceOf(liquidator).call()

    assert after - before == 22 * WAD // 10
    _, _, remaining_collateral, remaining_debt, *_ = vaults.functions.vaults(unsafe).call()
    assert remaining_collateral == 78 * WAD // 10
    assert remaining_debt == 5_000 * WAD


def test_oracle_updates_change_mint_capacity(protocol, w3):
    alice = protocol["alice"]
    vaults = protocol["vaults"]
    collateral = protocol["collateral"]
    oracle = protocol["oracle"]

    collateral.functions.approve(vaults.address, 10 * WAD).transact({"from": alice})
    vaults.functions.open_vault(collateral.address).transact({"from": alice})
    vault_id = vaults.functions.latest_vault_by_owner(alice).call()
    vaults.functions.deposit(vault_id, 10 * WAD).transact({"from": alice})

    vaults.functions.mint(vault_id, 6_000 * WAD).transact({"from": alice})
    oracle.functions.push_price(collateral.address, 700 * WAD).transact({"from": protocol["admin"]})

    with pytest.raises(Exception):
        vaults.functions.mint(vault_id, 1 * WAD).transact({"from": alice})


def _prepare_deficit(protocol, w3):
    alice = protocol["alice"]
    redeemer = protocol["redeemer"]
    stable = protocol["stable"]
    collateral = protocol["collateral"]
    oracle = protocol["oracle"]
    stability = protocol["stability"]

    open_vault(w3, protocol, alice, 10 * WAD, 6_000 * WAD)
    stable.functions.transfer(redeemer, 5_000 * WAD).transact({"from": alice})
    oracle.functions.push_price(collateral.address, 500 * WAD).transact({"from": protocol["admin"]})
    stable.functions.approve(stability.address, 5_000 * WAD).transact({"from": redeemer})


def test_redemption_preview_reports_deficit_adjustment(protocol, w3):
    _prepare_deficit(protocol, w3)
    stability = protocol["stability"]

    module_value, _ = stability.functions.preview_redeem(100 * WAD).call()
    pro_rata_value, _ = stability.functions.preview_redeem_pro_rata(100 * WAD).call()

    assert pro_rata_value == 100 * WAD * 5_000 // 6_000
    assert module_value > pro_rata_value
    assert module_value > 98 * WAD


def test_fragmented_redemption_drains_more_than_single_redeem(protocol, w3, compiled):
    # Single-redeem branch.
    _prepare_deficit(protocol, w3)
    redeemer = protocol["redeemer"]
    collateral = protocol["collateral"]
    stable = protocol["stable"]
    vaults = protocol["vaults"]
    stability = protocol["stability"]

    before_single = collateral.functions.balanceOf(redeemer).call()
    stability.functions.redeem(5_000 * WAD, 0).transact({"from": redeemer})
    single_out = collateral.functions.balanceOf(redeemer).call() - before_single
    single_remaining_value = vaults.functions.reserve_value(collateral.address).call()
    single_supply = stable.functions.totalSupply().call()

    # Fresh protocol for the fragmented branch. Pytest fixtures are function-scoped,
    # so redeploying with the same helper pattern keeps the comparison explicit.
    from conftest import deploy

    admin = w3.eth.accounts[0]
    alice = w3.eth.accounts[1]
    redeemer = w3.eth.accounts[2]
    liquidator = w3.eth.accounts[3]
    stable2 = deploy(w3, compiled, "HalberdUSD", admin)
    collateral2 = deploy(w3, compiled, "HalberdCollateral", admin)
    oracle2 = deploy(w3, compiled, "HalberdOracle", admin)
    risk2 = deploy(w3, compiled, "HalberdRiskEngine", admin)
    vaults2 = deploy(w3, compiled, "HalberdVaults", stable2.address, oracle2.address, risk2.address, admin)
    stability2 = deploy(
        w3,
        compiled,
        "HalberdStabilityModule",
        stable2.address,
        vaults2.address,
        oracle2.address,
        risk2.address,
        collateral2.address,
        admin,
    )
    stable2.functions.set_vault(vaults2.address).transact({"from": admin})
    stable2.functions.set_stability_module(stability2.address).transact({"from": admin})
    vaults2.functions.set_stability_module(stability2.address).transact({"from": admin})
    oracle2.functions.set_feed(collateral2.address, 1000 * WAD, 10**9, 10_000).transact({"from": admin})
    risk2.functions.configure_market(collateral2.address, 15_000, 12_000, 1_000, 50_000 * WAD, 100 * WAD, 25_000 * WAD).transact({"from": admin})
    risk2.functions.set_fees(collateral2.address, 0, 0).transact({"from": admin})
    for account in [alice, redeemer, liquidator]:
        collateral2.functions.transfer(account, 1_000 * WAD).transact({"from": admin})
    protocol2 = {
        "admin": admin,
        "alice": alice,
        "redeemer": redeemer,
        "liquidator": liquidator,
        "stable": stable2,
        "collateral": collateral2,
        "oracle": oracle2,
        "risk": risk2,
        "vaults": vaults2,
        "stability": stability2,
    }
    _prepare_deficit(protocol2, w3)

    before_frag = collateral2.functions.balanceOf(redeemer).call()
    for _ in range(50):
        stability2.functions.redeem(100 * WAD, 0).transact({"from": redeemer})
    fragmented_out = collateral2.functions.balanceOf(redeemer).call() - before_frag
    fragmented_remaining_value = vaults2.functions.reserve_value(collateral2.address).call()
    fragmented_supply = stable2.functions.totalSupply().call()

    assert fragmented_supply == single_supply == 1_000 * WAD
    assert fragmented_out > single_out
    assert fragmented_out - single_out > 1 * WAD
    assert fragmented_remaining_value < single_remaining_value
    assert vaults2.functions.backing_ratio_bps(collateral2.address).call() < 1_000
