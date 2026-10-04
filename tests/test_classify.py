"""DORA Art. 18 classification-as-code (drills/lib/classify.py).

Mapping: DORA Art. 18 / Commission Delegated Regulation (EU) 2024/1772, as *approximated*
by the module (illustrative thresholds, not a transcription of the RTS)."""
import copy

import pytest

QUIET = {
    "clients_affected_pct": 0,
    "geographical_spread_member_states": 1,
    "economic_impact_eur": 0,
    "reputational_impact": "low",
    "critical_service_affected": False,
}


def run(classify, record_overrides=None, **profile_overrides):
    record = {"measured_rto_seconds": 60, "measured_rpo_records_lost": 0, "integrity_check": "pass"}
    record.update(record_overrides or {})
    profile = {**copy.deepcopy(QUIET), **profile_overrides}
    return classify.classify(record, profile)


def test_quiet_incident_is_non_major(classify):
    assert run(classify) == ("non-major", [])


def test_single_primary_criterion_alone_is_not_major(classify):
    cls, tripped = run(classify, clients_affected_pct=50)
    assert cls == "non-major"
    assert tripped == ["clients_counterparties_affected"]


def test_primary_plus_one_other_is_major(classify):
    cls, tripped = run(classify, clients_affected_pct=50, economic_impact_eur=500_000)
    assert cls == "major"
    assert set(tripped) == {"clients_counterparties_affected", "economic_impact"}


def test_reputational_is_also_a_primary_criterion(classify):
    cls, _ = run(classify, reputational_impact="high", critical_service_affected=True)
    assert cls == "major"


def test_two_secondary_criteria_without_a_primary_stay_non_major(classify):
    cls, tripped = run(classify, economic_impact_eur=500_000, geographical_spread_member_states=3)
    assert cls == "non-major"
    assert len(tripped) == 2


@pytest.mark.parametrize(
    "seconds,expected",
    [(2 * 3600, False), (2 * 3600 + 1, True)],
)
def test_duration_threshold_is_strictly_greater_than(classify, seconds, expected):
    _, tripped = run(classify, {"measured_rto_seconds": seconds})
    assert ("duration" in tripped) is expected


def test_data_loss_from_lost_records(classify):
    _, tripped = run(classify, {"measured_rpo_records_lost": 1})
    assert tripped == ["data_losses"]


def test_data_loss_from_failed_integrity_check_even_with_zero_lost(classify):
    _, tripped = run(classify, {"integrity_check": "fail"})
    assert tripped == ["data_losses"]


def test_missing_measurements_do_not_crash_or_trip(classify):
    cls, tripped = classify.classify({"integrity_check": "pass"}, copy.deepcopy(QUIET))
    assert (cls, tripped) == ("non-major", [])


@pytest.mark.parametrize("pct,expected", [(10.0, False), (10.01, True)])
def test_clients_threshold_boundary(classify, pct, expected):
    _, tripped = run(classify, clients_affected_pct=pct)
    assert ("clients_counterparties_affected" in tripped) is expected


def test_geographic_threshold_is_inclusive(classify):
    _, tripped = run(classify, geographical_spread_member_states=2)
    assert "geographical_spread" in tripped


def test_unknown_scenario_profile_raises(classify):
    with pytest.raises(KeyError):
        classify.load_profile("no-such-scenario")


def test_every_shipped_scenario_has_a_complete_profile(classify, repo):
    scenarios = {p.stem for p in (repo / "drills" / "scenarios").glob("*.yaml")}
    for name in scenarios:
        profile = classify.load_profile(name)
        assert set(QUIET) <= set(profile), f"{name} profile missing keys"


def test_no_shipped_scenario_classifies_major_by_default(classify, repo):
    """Documented behaviour: profiles are not tuned to force 'major'."""
    for p in (repo / "drills" / "scenarios").glob("*.yaml"):
        # A clean run: fast recovery, no data loss. credential-compromise has a 'medium'
        # reputational profile, so adding data loss would legitimately make it major.
        record = {"measured_rto_seconds": 110, "measured_rpo_records_lost": 0, "integrity_check": "pass"}
        cls, _ = classify.classify(record, classify.load_profile(p.stem))
        assert cls == "non-major", p.stem


def test_credential_compromise_plus_data_loss_is_major(classify):
    """Reputational 'medium' is a primary criterion; one more criterion makes it major."""
    record = {"measured_rto_seconds": 10, "measured_rpo_records_lost": 5, "integrity_check": "pass"}
    cls, tripped = classify.classify(record, classify.load_profile("credential-compromise"))
    assert cls == "major" and "reputational_impact" in tripped
