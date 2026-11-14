"""Conservative, rule-based outcome extraction from Delhi High Court orders.

Returns (outcome, evidence) where outcome is one of:
  petitioner   the petitioner/appellant/plaintiff side got what it asked for
  respondent   the petition/appeal/suit/application failed
  appointed    an arbitrator was appointed (section 11); usually unopposed,
               so it is shown but not counted as a contested win
  consent      allowed by consent or without opposition (not a contested win)
  partly       partly allowed (mixed; never counted as a win)
  settled      settled, compromised, mediated or decreed on consent
  withdrawn    withdrawn or not pressed
  infructuous  disposed of as infructuous / without adjudication
  interim      an interim or procedural order (listing, notice, adjournment)
  unknown      no reliable final-outcome sentence found

Only `petitioner` and `respondent` are outcome-eligible. Everything else is
excluded from favourable-rate maths, as the blueprint requires. The evidence
is the exact sentence the decision was read from, so a reviewer can check it.
"""
import re

_WS = re.compile(r"\s+")
_FOOTER = re.compile(
    r"(Digitally )?Signed By\s*:?.{0,60}?Signing Date\s*:?\s*[\d.]+\s*[\d:]*"
    r"|Signature Not Verified|Click here to check corrigendum, if any"
    r"|(Digitally )?Signed By\s*:?\s*[A-Z .]{2,40}"
    r"|Page \d+ of \d+"
    r"|The authenticity of the order can be re-verified.*?QR code shown above\.?"
    r"|The Order is downloaded from the DHC Server on [\d/]+ at [\d:]+", re.I)

# Order matters: the first family that matches in the operative part wins.
# Each rule has the size of the tail (in characters) it may look at.
_RULES = [
    ("settled", 1400, re.compile(
        r"in terms of the (?:aforesaid |said |above )?(?:terms of )?(?:settlement|compromise|mou|memorandum of (?:settlement|understanding))"
        r"|parties (?:have|had)? ?(?:amicably )?(?:arrived at|entered into|reached) (?:a |an )?(?:amicable )?(?:settlement|compromise)"
        r"|parties (?:have|had) (?:amicably )?settled|settled (?:all )?(?:their|the) disputes?"
        r"|(?:remain|be) bound by the terms (?:and conditions )?of (?:the )?(?:settlement|compromise)"
        r"|consent decree|mediation (?:has|had)? ?(?:been )?(?:successful|succeeded)|disputes? (?:has|have) been (?:amicably )?(?:settled|resolved)", re.I)),
    ("consent", 1200, re.compile(
        r"(?:with|by) (?:the )?consent of (?:learned )?(?:counsel for )?(?:the |both )?parties|by consent|consent order|no objection (?:is raised|to the|if the)|does not oppose|not opposed|fairly concedes|jointly (?:prayed|requested|submitted)", re.I)),
    ("withdrawn", 1200, re.compile(
        r"dismissed as withdrawn|disposed of as withdrawn|withdrawn with liberty|stands? withdrawn|leave to withdraw|seeks? to withdraw"
        r"|not pressed|does not press|is withdrawn|permitted to be withdrawn", re.I)),
    ("infructuous", 1000, re.compile(r"infructuous|has become academic|rendered academic", re.I)),
    ("partly", 1000, re.compile(
        r"partly allowed|partially allowed|allowed in part|allowed to the (?:aforesaid |above |limited )?extent|partly decreed|partly set aside|modified to the extent", re.I)),
    ("petitioner", 1200, re.compile(
        r"(?:petition|appeal|suit|revision|writ petition|bail application|objections?)s?\s+(?:is|are|stands?|is hereby|are hereby)\s+(?:accordingly\s+)?(?:allowed|decreed)"
        r"|(?:impugned|arbitral) (?:award|order|judgment)s?\b[^.]{0,80}\b(?:is|are|stands?|hereby) (?:set aside|quashed)"
        r"|(?:fir|complaint|summoning order)[^.]{0,120}\b(?:is|are|stands?|hereby) quashed"
        r"|(?:petitioner|applicant|accused) (?:is|be) (?:admitted|released) (?:to|on) (?:regular |interim )?bail"
        r"|decree (?:of|for) [^.]{0,60}(?:is|be) passed in favou?r of the plaintiff"
        r"|(?:permanent|perpetual) injunction[^.]{0,80}(?:is|are) (?:granted|passed)", re.I)),
    ("appointed", 2600, re.compile(
        r"(?:is|are) (?:hereby )?appointed as (?:the )?(?:sole |presiding |learned )?arbitra(?:tor|l tribunal)"
        r"|appoint(?:s|ed)?\b.{0,220}?\bas (?:the )?(?:sole |presiding |learned )?arbitrator", re.I | re.S)),
    ("respondent", 1200, re.compile(
        r"(?:petition|appeal|suit|revision|writ petition|bail application|objections?|plaint)s?\s+(?:is|are|stands?|is hereby|are hereby|being devoid of merit,? (?:is|are))\s+(?:accordingly\s+)?(?:dismissed|rejected)"
        r"|(?:we|i) find no merit in the (?:present |instant |captioned )?(?:petition|appeal|suit|objections|application)|plaint (?:is|stands) rejected"
        r"|(?:impugned|arbitral) (?:award|order|judgment)s? (?:is|are) (?:upheld|affirmed|sustained)", re.I)),
    ("interim", 900, re.compile(
        r"list (?:the matter )?(?:on|for|before)|re-?notify|issue notice|adjourned|next date of hearing|stand over|renotified|reply be filed|rejoinder", re.I)),
]


def _evidence(tail: str, m: re.Match) -> str:
    start = max(tail.rfind(". ", 0, m.start()) + 2, m.start() - 220, 0)
    stop = tail.find(". ", m.end())
    stop = len(tail) if stop == -1 or stop - m.end() > 220 else stop + 1
    return tail[start:stop].strip()


def _operative_tail(text: str, chars: int = 2200) -> str:
    t = _WS.sub(" ", text)
    # Strip page footers and signature stamps, which repeat on every page.
    t = re.split(r"This is a digitally signed order", t)[0]
    t = _FOOTER.sub(" ", t)
    return _WS.sub(" ", t)[-chars:]


def extract_outcome(text: str) -> tuple[str, str]:
    if not text or len(text) < 200:
        return "unknown", ""
    tail = _operative_tail(text, 2600)
    for label, size, rx in _RULES:
        window = tail[-size:]
        hits = list(rx.finditer(window))
        if hits:
            return label, _evidence(window, hits[-1])[:400]
    return "unknown", ""


def is_final(outcome: str) -> bool:
    return outcome in {"petitioner", "respondent", "appointed", "consent", "partly", "settled", "withdrawn", "infructuous"}
