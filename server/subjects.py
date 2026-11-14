"""Plain-language subjects mapped to official Delhi High Court case types.

Mirrors lib/core/public_records/case_type_subjects.dart in the app.
"""


def _n(t: str) -> str:
    return t.upper().replace(" ", "")


SUBJECTS = [
    ("arbitration", "Arbitration", ["arbitration", "arbitral", "arbitrator", "award", "section 9", "section 11", "section 34", "section 37"],
     lambda t: _n(t).startswith(("ARB", "O.M.P", "OMP"))),
    ("ip", "Intellectual property", ["trademark", "trade mark", "patent", "copyright", "design", "intellectual property", "infringement", "passing off", "brand"],
     lambda t: "IPD" in _n(t) or _n(t) == "I.P.A."),
    ("commercial", "Commercial disputes", ["commercial", "contract", "breach", "recovery", "suit", "damages", "injunction"],
     lambda t: "COMM" in _n(t)),
]


def detect(question: str):
    # "patent illegality" is an arbitration ground, not a patent dispute.
    q = question.lower().replace("patent illegality", "illegality")
    return [(sid, label, match) for sid, label, kws, match in SUBJECTS if any(k in q for k in kws)]
