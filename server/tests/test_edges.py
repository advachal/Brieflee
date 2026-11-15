import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tool", "knowledge"))
import build_edges as be  # noqa: E402


def _db():
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE records(id, case_number, case_type, decision_date, court, petitioner, respondent)")
    db.executemany("INSERT INTO records VALUES (?,?,?,?,?,?,?)", [
        ("HC1", "W.P.(C) 7124/2016", "W.P.(C)", "2017-01-24", "7_26", "JAWAHAR LAL NEHRU COLLEGE", "NCTE"),
        ("HC2", "LPA 100/2017", "LPA", "2017-02-08", "7_26", "JAWAHAR LAL NEHRU COLLEGE", "NCTE"),
        ("HC3", "W.P.(C) 9000/2016", "W.P.(C)", "2017-02-08", "7_26", "A", "B"),
        ("SC_2022_13_1064_1080", "CIVIL APPEAL No. 4832/2022", "CIVIL APPEAL", "2022-08-01", "sc", "SYSKA LED LIGHTS", "GM MODULAR"),
        ("HC4", "W.P.(C) 1/2024", "W.P.(C)", "2024-03-01", "7_26", "X", "Y"),
    ])
    return be.Index(db)


def test_norm_type():
    assert be.norm_type("W.P.(C) No.") == be.norm("W.P.(C)")
    assert be.norm_type("Writ Petition (C)") == "WPC"


def test_appeal_of_and_skips():
    idx = _db()
    text = ("This appeal impugns the order of the learned Single Judge dated 24.01.2017 in W.P.(C) No.7124/2016. "
            "Also see W.P.(C) 9000/2016 decided today, and our own LPA 100/2017.")
    e = {(d, k) for _, d, k, _ in be.edges_for("HC2", text, idx)}
    assert ("HC1", "appeal_of") in e
    assert not any(d in ("HC2", "HC3") for d, _ in e)  # itself, and a matter decided the same day


def test_scr_and_named_cites():
    idx = _db()
    e = {(d, k) for _, d, k, _ in be.edges_for("HC4", "as held in [2022] 13 S.C.R. 1070", idx)}
    assert ("SC_2022_13_1064_1080", "cites") in e
    e = {(d, k) for _, d, k, _ in be.edges_for("HC4", "Syska LED Lights v. GM Modular, (2022) 9 SCC 100", idx)}
    assert ("SC_2022_13_1064_1080", "cites") in e


def test_connected_matter_list_skipped():
    idx = _db()
    text = "W.P.(C) 7124/2016, W.P.(C) 11/2016, W.P.(C) 12/2016, W.P.(C) 13/2016 heard together"
    assert not be.edges_for("HC4", text, idx)


def test_bail_application_of_year():
    import sqlite3 as s
    db = s.connect(":memory:")
    db.execute("CREATE TABLE records(id, case_number, case_type, decision_date, court, petitioner, respondent)")
    db.executemany("INSERT INTO records VALUES (?,?,?,?,?,?,?)", [
        ("HC9", "BAIL APPLN. 196/2022", "BAIL APPLN.", "2022-03-01", "7_26", "A", "STATE"),
        ("SC_2022_3_548_552", "CRIMINAL APPEAL No. 500/2022", "CRIMINAL APPEAL", "2022-04-01", "sc", "STATE", "A")])
    idx = be.Index(db)
    text = "order of a Single Judge of the High Court of Delhi in Bail Application No 196 of 2022 is set aside."
    assert {(d, k) for _, d, k, _ in be.edges_for("SC_2022_3_548_552", text, idx)} == {("HC9", "appeal_of")}
