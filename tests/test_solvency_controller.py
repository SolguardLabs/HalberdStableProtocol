import pytest

from conftest import WAD, deploy


@pytest.fixture()
def controller(w3, compiled):
    return deploy(w3, compiled, "HalberdSolvencyController", w3.eth.accounts[0])


def test_default_solvency_policy(controller):
    assert controller.functions.reserve_haircut_bps().call() == 1_000
    assert controller.functions.liquidation_recovery_bps().call() == 7_500
    assert controller.functions.capital_buffer_bps().call() == 750
    assert controller.functions.target_coverage_bps().call() == 12_500
    assert controller.functions.concentration_limit_bps().call() == 4_000
    assert controller.functions.policy_version().call() == 1


def test_projection_exposes_resource_and_obligation_waterfall(controller):
    view = controller.functions.project(
        12_000_000 * WAD,
        8_000_000 * WAD,
        500_000 * WAD,
        2_000_000 * WAD,
        100_000 * WAD,
        4_000_000 * WAD,
    ).call()

    assert view[0] == 10_800_000 * WAD
    assert view[1] == 1_500_000 * WAD
    assert view[2] == 600_000 * WAD
    assert view[3] == 12_300_000 * WAD
    assert view[4] == 9_200_000 * WAD
    assert view[5] == 3_100_000 * WAD
    assert view[6] == 0
    assert view[7] == 13_369
    assert view[8] == 2_857
    assert view[9] == 3


def test_projection_classifies_a_liquidity_gap(controller):
    view = controller.functions.project(
        5_000_000 * WAD,
        8_000_000 * WAD,
        1_000_000 * WAD,
        0,
        500_000 * WAD,
        4_000_000 * WAD,
    ).call()

    assert view[3] == 4_500_000 * WAD
    assert view[4] == 10_100_000 * WAD
    assert view[5] == 0
    assert view[6] == 5_600_000 * WAD
    assert view[7] == 4_455
    assert view[9] == 0


def test_policy_update_is_versioned(controller, w3):
    admin = w3.eth.accounts[0]
    controller.functions.configure(2_000, 6_000, 1_000, 14_000, 3_500).transact(
        {"from": admin}
    )

    assert controller.functions.reserve_haircut_bps().call() == 2_000
    assert controller.functions.target_coverage_bps().call() == 14_000
    assert controller.functions.policy_version().call() == 2


def test_non_admin_cannot_change_policy(controller, w3):
    with pytest.raises(Exception):
        controller.functions.configure(0, 10_000, 0, 10_000, 10_000).transact(
            {"from": w3.eth.accounts[2]}
        )


@pytest.mark.parametrize(
    "values",
    [
        (10_001, 7_500, 750, 12_500, 4_000),
        (1_000, 10_001, 750, 12_500, 4_000),
        (1_000, 7_500, 10_001, 12_500, 4_000),
        (1_000, 7_500, 750, 9_999, 4_000),
        (1_000, 7_500, 750, 50_001, 4_000),
        (1_000, 7_500, 750, 12_500, 10_001),
    ],
)
def test_invalid_policy_bounds_are_rejected(controller, w3, values):
    with pytest.raises(Exception):
        controller.functions.configure(*values).transact({"from": w3.eth.accounts[0]})


def test_mint_headroom_uses_target_coverage(controller):
    headroom = controller.functions.mint_headroom(
        20_000_000 * WAD, 10_000_000 * WAD, 0
    ).call()
    assert headroom == 4_400_000 * WAD


def test_mint_headroom_closes_below_target(controller):
    headroom = controller.functions.mint_headroom(
        10_000_000 * WAD, 10_000_000 * WAD, 0
    ).call()
    assert headroom == 0


def test_concentration_moves_an_ample_projection_to_guarded(controller):
    view = controller.functions.project(
        20_000_000 * WAD,
        8_000_000 * WAD,
        0,
        0,
        0,
        15_000_000 * WAD,
    ).call()
    assert view[6] == 0
    assert view[7] > 12_500
    assert view[8] == 7_500
    assert view[9] == 2


def test_empty_projection_has_unbounded_coverage(controller):
    view = controller.functions.project(0, 0, 0, 0, 0, 0).call()
    assert view[4] == 0
    assert view[7] == 2**256 - 1
    assert view[9] == 3


def test_recapitalization_matches_projected_gap(controller):
    gap = controller.functions.recapitalization_required(
        5_000_000 * WAD,
        8_000_000 * WAD,
        1_000_000 * WAD,
        0,
        500_000 * WAD,
    ).call()
    assert gap == 5_600_000 * WAD
