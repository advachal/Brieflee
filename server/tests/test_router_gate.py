"""Fast checks with no database or AI key: the router and the answer gate."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import gate  # noqa: E402
import router  # noqa: E402


def test_case_number_is_lookup():
    r = router.route("Show me CS(COMM) 412/2022")
    assert r["route"] == "lookup" and r["case_number"] == ("CS(COMM)", "412", "2022")
    assert router.route("O.M.P. (COMM) 311/2021")["case_number"][0] == "O.M.P. (COMM)"


def test_parties_are_lookup():
    r = router.route("GM Modular v. Syska LED Lights")
    assert r["route"] == "lookup" and r["parties"] == ("GM Modular", "Syska LED Lights")


def test_generic_party_is_not_lookup():
    assert router.route("Find decisions in which the Union of India was respondent in pension cases")["route"] == "simple"


def test_counting_and_comparison():
    assert router.route("How many NDPS bail applications were granted in 2024?")["route"] == "aggregate"
    assert router.route("Compare two advocates in trademark appeals")["route"] == "complex"
    assert router.route("Interim injunction to restrain encashment of a bank guarantee")["route"] == "simple"


def test_gold_set_routes():
    qs = json.load(open(os.path.join(HERE, "..", "..", "tool", "eval", "goldset", "questions.json")))
    ok = sum(router.route(x["q"])["route"] == x["route"] for x in qs)
    assert ok / len(qs) >= 0.95, f"router agrees on {ok}/{len(qs)}"


TEXTS = {"DLHC010000012024_2024-01-02": "The petition under Section 34 is dismissed, as the award is not patently illegal."}


def test_gate_passes_grounded_answer():
    a = 'The court held the award was "not patently illegal" [DLHC010000012024_2024-01-02].'
    v = gate.check(a, list(TEXTS), TEXTS, {"DLHC010000012024_2024-01-02": {"relevance": 3}}, found=1)
    assert v["passed"] and v["thin_evidence"]
    shown, kind = gate.apply(a, v)
    assert kind == "generated_grounded_thin" and shown.startswith("The evidence is thin")


def test_gate_blocks_unknown_citation_and_bad_quote():
    a = 'See [DLHC099999992024_2024-01-02], which says "the arbitrator must always be removed for bias".'
    v = gate.check(a, list(TEXTS), TEXTS, None, found=5)
    assert not v["passed"]
    assert v["unknown_citations"] == ["DLHC099999992024_2024-01-02"]
    assert v["unmatched_quotes"]
    shown, kind = gate.apply(a, v)
    assert kind == "withheld_by_gate" and shown.startswith("The AI summary was withheld")


def test_gate_blocks_uncited_answer():
    v = gate.check("Counsel X wins most arbitration cases.", list(TEXTS), TEXTS, None, found=5)
    assert not v["passed"] and "cites no decision" in v["problems"]
