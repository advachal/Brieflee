"""Plain-language subjects mapped to official Delhi High Court case types.

Mirrors lib/core/public_records/case_type_subjects.dart in the app.
"""


def _n(t: str) -> str:
    return t.upper().replace(" ", "")


SUBJECTS = [
    ("arbitration", "Arbitration", ["arbitration", "arbitral", "arbitrator", "award", "section 34", "29a"],
     lambda t: _n(t).startswith(("ARB", "O.M.P", "OMP"))),
    ("ip", "Intellectual property", ["trademark", "trade mark", "patent", "copyright", "design", "intellectual property", "infringement", "passing off", "brand"],
     lambda t: "IPD" in _n(t) or _n(t) == "I.P.A."),
    ("commercial", "Commercial disputes", ["commercial suit", "commercial dispute", "contract", "breach", "recovery", "damages"],
     lambda t: "COMM" in _n(t)),
    ("bail", "Bail", ["bail", "section 438", "section 439", "section 480", "section 482 bnss", "section 483", "ndps"],
     lambda t: "BAIL" in _n(t) or "CRL" in _n(t) or "CRIMINAL" in _n(t)),
    ("quashing", "Quashing of FIR or proceedings", ["quash", "section 482", "section 528", "fir"],
     lambda t: _n(t).startswith(("CRL.M.C", "W.P.(CRL", "WRITPETITION(CRIMINAL")) or "CRIMINAL" in _n(t)),
    ("criminal_appeal", "Criminal appeals", ["conviction", "acquittal", "criminal appeal", "sentence", "murder", "section 302", "section 376"],
     lambda t: _n(t).startswith(("CRL.A", "CRL.REV", "DEATHSENTENCE")) or "CRIMINAL" in _n(t)),
    ("cheque", "Cheque bounce", ["cheque", "section 138", "negotiable instruments"],
     lambda t: "CRL" in _n(t) or "CRIMINAL" in _n(t)),
    ("service", "Service and employment", ["service", "termination", "promotion", "pension", "seniority", "disciplinary", "employment", "labour", "workman"],
     lambda t: _n(t).startswith(("W.P.(C)", "LPA", "WRITPETITION(CIVIL)", "CIVILAPPEAL"))),
    ("matrimonial", "Family and matrimonial", ["divorce", "maintenance", "custody", "matrimonial", "section 125", "domestic violence", "hindu marriage"],
     lambda t: _n(t).startswith(("MAT", "CRL.REV.P", "TRANSFERPETITION"))),
    ("tax", "Tax", ["income tax", "gst", "customs", "excise", "assessment", "reassessment", "section 148", "tax"],
     lambda t: _n(t).startswith(("ITA", "W.P.(C)", "CUSAA", "SERTA", "CIVILAPPEAL"))),
    ("company", "Company and insolvency", ["insolvency", "ibc", "winding up", "company petition", "oppression", "liquidation"],
     lambda t: _n(t).startswith(("CO.", "COMPANY", "CIVILAPPEAL"))),
    ("property", "Property and civil suits", ["property", "possession", "eviction", "tenant", "landlord", "partition", "specific performance", "sale deed"],
     lambda t: _n(t).startswith(("RFA", "RSA", "CS(OS)", "RC.REV", "CM(M)", "CIVILAPPEAL"))),
]


def detect(question: str):
    # "patent illegality" is an arbitration ground, not a patent dispute.
    q = question.lower().replace("patent illegality", "illegality")
    return [(sid, label, match) for sid, label, kws, match in SUBJECTS if any(k in q for k in kws)]
