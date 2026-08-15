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

    oracle.functions.push_price(collateral.address, 500 * WAD).transact(
        {"from": protocol["admin"]}
    )
    assert vaults.functions.health_bps(unsafe).call() == 8_333

    before = collateral.functions.balanceOf(liquidator).call()
    stable.functions.approve(vaults.address, 1_000 * WAD).transact(
        {"from": liquidator}
    )
    vaults.functions.liquidate(unsafe, 1_000 * WAD).transact(
        {"from": liquidator}
    )
    after = collateral.functions.balanceOf(liquidator).call()

    assert after - before == 22 * WAD // 10
    _, _, remaining_collateral, remaining_debt, *_ = vaults.functions.vaults(
        unsafe
    ).call()
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
    oracle.functions.push_price(collateral.address, 700 * WAD).transact(
        {"from": protocol["admin"]}
    )

    with pytest.raises(Exception):
        vaults.functions.mint(vault_id, 1 * WAD).transact({"from": alice})


def test_solvent_redemption_returns_par_value(protocol, w3):
    alice = protocol["alice"]
    redeemer = protocol["redeemer"]
    stable = protocol["stable"]
    collateral = protocol["collateral"]
    stability = protocol["stability"]

    open_vault(w3, protocol, alice, 10 * WAD, 5_000 * WAD)
    stable.functions.transfer(redeemer, 500 * WAD).transact({"from": alice})
    stable.functions.approve(stability.address, 500 * WAD).transact(
        {"from": redeemer}
    )
    before = collateral.functions.balanceOf(redeemer).call()
    stability.functions.redeem(500 * WAD, 5 * WAD // 10).transact(
        {"from": redeemer}
    )

    assert collateral.functions.balanceOf(redeemer).call() - before == 5 * WAD // 10
    assert stable.functions.totalSupply().call() == 4_500 * WAD


def test_guardian_can_pause_and_admin_can_resume(protocol):
    admin = protocol["admin"]
    guardian = protocol["liquidator"]
    stability = protocol["stability"]

    stability.functions.set_guardian(guardian).transact({"from": admin})
    stability.functions.pause().transact({"from": guardian})
    assert stability.functions.paused().call() is True

    with pytest.raises(Exception):
        stability.functions.deposit(1).transact({"from": protocol["alice"]})

    stability.functions.unpause().transact({"from": admin})
    assert stability.functions.paused().call() is False
