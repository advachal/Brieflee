// ILLUSTRATIVE DEMO DATA.
//
// Every advocate, judge, party, case number, citation, passage and statistic
// in this file is fictional and generated deterministically for UI
// prototyping. None of it describes a real person or a real proceeding.
// Production builds must replace this with verified, permitted sources.

import '../models/models.dart';

/// Park–Miller generator: deterministic on the Dart VM and on the web.
class _Rng {
  _Rng(this._s);
  int _s;
  double next() {
    _s = (_s * 48271) % 2147483647;
    return _s / 2147483647;
  }

  int nextInt(int max) => (next() * max).floor().clamp(0, max - 1);
  bool chance(double p) => next() < p;
  T pick<T>(List<T> xs) => xs[nextInt(xs.length)];
  T weighted<T>(Map<T, double> w) {
    final total = w.values.fold<double>(0, (a, b) => a + b);
    var r = next() * total;
    for (final e in w.entries) {
      r -= e.value;
      if (r <= 0) return e.key;
    }
    return w.keys.last;
  }
}

abstract final class DemoCategories {
  static const trademark = 'Trademark infringement';
  static const passingOff = 'Passing off';
  static const copyright = 'Copyright';
  static const patent = 'Patent';
  static const contract = 'Commercial contract';
  static const arbitration = 'Arbitration (interim measures)';

  static const all = [
    trademark,
    passingOff,
    copyright,
    patent,
    contract,
    arbitration,
  ];

  static const statutes = <String, List<String>>{
    trademark: [
      'Trade Marks Act, 1999 s.29',
      'Trade Marks Act, 1999 s.135',
      'CPC Order XXXIX',
    ],
    passingOff: ['Trade Marks Act, 1999 s.27', 'CPC Order XXXIX'],
    copyright: [
      'Copyright Act, 1957 s.51',
      'Copyright Act, 1957 s.55',
      'CPC Order XXXIX',
    ],
    patent: [
      'Patents Act, 1970 s.48',
      'Patents Act, 1970 s.108',
      'CPC Order XXXIX',
    ],
    contract: [
      'Commercial Courts Act, 2015',
      'Specific Relief Act, 1963 s.38',
      'Indian Contract Act, 1872 s.73',
    ],
    arbitration: [
      'Arbitration and Conciliation Act, 1996 s.9',
      'Arbitration and Conciliation Act, 1996 s.34',
    ],
  };
}

class DemoDataset {
  DemoDataset._({
    required this.courts,
    required this.judges,
    required this.rosters,
    required this.listings,
    required this.sittingNotices,
    required this.advocates,
    required this.judgments,
    required this.mentionOnlyCounts,
  });

  final List<Court> courts;
  final List<Judge> judges;
  final Map<String, CourtRoster> rosters;
  final List<CaseListing> listings;
  final List<SittingNotice> sittingNotices;
  final List<Advocate> advocates;
  final List<Judgment> judgments;
  final Map<String, int> mentionOnlyCounts;

  static final DemoDataset instance = _build();

  /// Fixed reference date so the dataset is stable across runs.
  static final DateTime referenceDate = DateTime(2026, 11, 1);

  Judgment? judgment(String id) {
    for (final j in judgments) {
      if (j.id == id) return j;
    }
    return null;
  }

  Advocate? advocate(String id) {
    for (final a in advocates) {
      if (a.id == id) return a;
    }
    return null;
  }

  Judge? judge(String id) {
    for (final j in judges) {
      if (j.id == id) return j;
    }
    return null;
  }

  String judgeName(String id) => judge(id)?.name ?? 'Unknown judge';

  static DemoDataset _build() {
    final ref = referenceDate;
    final courts = [
      const Court(
        id: 'dhc',
        name: 'Delhi High Court',
        shortName: 'DHC',
        type: CourtType.highCourt,
        jurisdiction: 'NCT of Delhi: original and appellate',
        divisions: [
          'Original Side',
          'Commercial Division',
          'IP Division',
          'Appellate Side',
        ],
        caseCategories: DemoCategories.all,
        support: CourtSupport.pilot,
      ),
      const Court(
        id: 'sci',
        name: 'Supreme Court of India',
        shortName: 'SCI',
        type: CourtType.supremeCourt,
        jurisdiction: 'All India: appellate, original and advisory',
        divisions: [
          'Civil Appeals',
          'Special Leave Petitions',
          'Writ Petitions',
        ],
        caseCategories: [
          'Civil appeal',
          'Special leave petition',
          'Constitutional',
        ],
        support: CourtSupport.planned,
      ),
      const Court(
        id: 'bhc',
        name: 'Bombay High Court',
        shortName: 'BHC',
        type: CourtType.highCourt,
        jurisdiction: 'Maharashtra, Goa, Dadra & Nagar Haveli and Daman & Diu',
        divisions: ['Original Side', 'Commercial Division', 'Appellate Side'],
        caseCategories: [
          'Commercial suit',
          'Intellectual property',
          'Arbitration',
        ],
        support: CourtSupport.planned,
      ),
      const Court(
        id: 'nclat',
        name: 'National Company Law Appellate Tribunal',
        shortName: 'NCLAT',
        type: CourtType.tribunal,
        jurisdiction: 'Appeals from NCLT benches',
        divisions: ['Principal Bench, New Delhi', 'Chennai Bench'],
        caseCategories: ['Insolvency', 'Company law', 'Competition'],
        support: CourtSupport.planned,
      ),
    ];

    const judgeNames = [
      'Justice Demo Alpha',
      'Justice Demo Bravo',
      'Justice Demo Charlie',
      'Justice Demo Delta',
      'Justice Demo Echo',
      'Justice Demo Foxtrot',
      'Justice Demo Golf',
    ];
    final judges = [
      for (var i = 0; i < judgeNames.length; i++)
        Judge(
          id: 'j${i + 1}',
          name: judgeNames[i],
          courtId: 'dhc',
          designation: i == 1 ? 'Judge (Division Bench presiding)' : 'Judge',
          isSitting: i != 6,
          verification: i == 5
              ? VerificationStatus.unverified
              : VerificationStatus.verified,
        ),
    ];

    final v12 = RosterVersion(
      id: 'dhc-roster-v12',
      courtId: 'dhc',
      label: 'Roster v12 (demo)',
      effectiveFrom: DateTime(2026, 10, 6),
      lastCheckedAt: DateTime(2026, 11, 14, 6, 0),
      sourceLabel: 'Official roster PDF (demo placeholder, not fetched)',
      verification: VerificationStatus.verified,
      assignments: [
        BenchAssignment(
          benchId: 'b-ip-21',
          judgeIds: ['j1'],
          courtRoom: 'Court 21',
          subjects: [
            DemoCategories.trademark,
            DemoCategories.passingOff,
            DemoCategories.copyright,
          ],
          effectiveFrom: DateTime(2026, 10, 6),
        ),
        BenchAssignment(
          benchId: 'db-2',
          judgeIds: ['j2', 'j4'],
          courtRoom: 'Court 2',
          subjects: ['Commercial appeals', 'IP appeals'],
          effectiveFrom: DateTime(2026, 10, 6),
        ),
        BenchAssignment(
          benchId: 'b-comm-14',
          judgeIds: ['j3'],
          courtRoom: 'Court 14',
          subjects: [DemoCategories.contract, DemoCategories.arbitration],
          effectiveFrom: DateTime(2026, 10, 6),
        ),
        BenchAssignment(
          benchId: 'b-pat-23',
          judgeIds: ['j5'],
          courtRoom: 'Court 23',
          subjects: [DemoCategories.patent],
          effectiveFrom: DateTime(2026, 10, 6),
        ),
        BenchAssignment(
          benchId: 'b-orig-30',
          judgeIds: ['j6'],
          courtRoom: 'Court 30',
          subjects: ['Original side: miscellaneous'],
          effectiveFrom: DateTime(2026, 10, 6),
        ),
      ],
    );
    final v11 = RosterVersion(
      id: 'dhc-roster-v11',
      courtId: 'dhc',
      label: 'Roster v11 (demo)',
      effectiveFrom: DateTime(2026, 7, 1),
      lastCheckedAt: DateTime(2026, 10, 5, 22, 0),
      sourceLabel: 'Official roster PDF (demo placeholder, not fetched)',
      verification: VerificationStatus.verified,
      assignments: [
        BenchAssignment(
          benchId: 'b-ip-21',
          judgeIds: ['j3'],
          courtRoom: 'Court 21',
          subjects: [
            DemoCategories.trademark,
            DemoCategories.passingOff,
            DemoCategories.copyright,
          ],
          effectiveFrom: DateTime(2026, 7, 1),
          effectiveTo: DateTime(2026, 10, 5),
        ),
        BenchAssignment(
          benchId: 'db-2',
          judgeIds: ['j2', 'j7'],
          courtRoom: 'Court 2',
          subjects: ['Commercial appeals', 'IP appeals'],
          effectiveFrom: DateTime(2026, 7, 1),
          effectiveTo: DateTime(2026, 10, 5),
        ),
        BenchAssignment(
          benchId: 'b-comm-14',
          judgeIds: ['j1'],
          courtRoom: 'Court 14',
          subjects: [DemoCategories.contract, DemoCategories.arbitration],
          effectiveFrom: DateTime(2026, 7, 1),
          effectiveTo: DateTime(2026, 10, 5),
        ),
        BenchAssignment(
          benchId: 'b-pat-23',
          judgeIds: ['j5'],
          courtRoom: 'Court 23',
          subjects: [DemoCategories.patent],
          effectiveFrom: DateTime(2026, 7, 1),
          effectiveTo: DateTime(2026, 10, 5),
        ),
      ],
    );

    final listings = [
      CaseListing(
        caseNumber: 'CS(COMM) 512/2026',
        courtId: 'dhc',
        listingDate: DateTime(2026, 11, 18),
        benchJudgeIds: const ['j1'],
        previousBenchJudgeIds: const ['j3'],
        courtRoom: 'Court 21',
        itemNumber: 14,
        causeListLabel: 'Advance cause list, 18 Nov 2026 (demo)',
        status: ListingStatus.benchChanged,
        verification: VerificationStatus.verified,
        lastCheckedAt: DateTime(2026, 11, 14, 6, 0),
      ),
      CaseListing(
        caseNumber: 'FAO(OS)(COMM) 77/2026',
        courtId: 'dhc',
        listingDate: DateTime(2026, 11, 20),
        benchJudgeIds: const ['j2', 'j4'],
        courtRoom: 'Court 2',
        itemNumber: 3,
        causeListLabel: 'Advance cause list, 20 Nov 2026 (demo)',
        status: ListingStatus.scheduled,
        verification: VerificationStatus.verified,
        lastCheckedAt: DateTime(2026, 11, 14, 6, 0),
      ),
      CaseListing(
        caseNumber: 'OMP(I)(COMM) 140/2026',
        courtId: 'dhc',
        listingDate: DateTime(2026, 11, 19),
        benchJudgeIds: const ['j3'],
        courtRoom: 'Court 14',
        itemNumber: 22,
        causeListLabel: 'Advance cause list, 19 Nov 2026 (demo)',
        status: ListingStatus.scheduled,
        verification: VerificationStatus.unverified,
        lastCheckedAt: DateTime(2026, 11, 13, 21, 0),
      ),
    ];

    final notices = [
      SittingNotice(
        id: 'sn-1',
        courtId: 'dhc',
        date: DateTime(2026, 11, 17),
        description:
            'Court 21 will not sit on 17 Nov 2026; urgent matters '
            'before Court 23 (demo notice).',
        affectedJudgeIds: const ['j1', 'j5'],
        verification: VerificationStatus.verified,
      ),
      SittingNotice(
        id: 'sn-2',
        courtId: 'dhc',
        date: DateTime(2026, 11, 21),
        description:
            'Court 30 listing for 21 Nov 2026 not found in the '
            'published cause list. Status unverified, not treated as absence.',
        affectedJudgeIds: const ['j6'],
        verification: VerificationStatus.unverified,
      ),
    ];

    // --- Advocates ----------------------------------------------------------
    // (id, name, chamber, since, areas, affinity per category, strength)
    final advocateSpecs = <_AdvSpec>[
      _AdvSpec('a1', 'Advocate A', 2004, {
        DemoCategories.trademark: 9,
        DemoCategories.passingOff: 6,
        DemoCategories.copyright: 3,
      }, 0.80),
      _AdvSpec('a2', 'Advocate B', 2008, {
        DemoCategories.trademark: 7,
        DemoCategories.copyright: 5,
        DemoCategories.passingOff: 3,
      }, 0.68),
      _AdvSpec('a3', 'Advocate C', 2012, {
        DemoCategories.trademark: 4,
        DemoCategories.passingOff: 4,
        DemoCategories.contract: 2,
      }, 0.54),
      _AdvSpec('a4', 'Advocate D', 2001, {
        DemoCategories.patent: 9,
        DemoCategories.trademark: 1.5,
      }, 0.66),
      _AdvSpec('a5', 'Advocate E', 2006, {
        DemoCategories.arbitration: 8,
        DemoCategories.contract: 8,
      }, 0.64),
      _AdvSpec('a6', 'Advocate F', 2019, {
        DemoCategories.trademark: 0.6,
        DemoCategories.contract: 0.6,
      }, 0.55),
      _AdvSpec('a7', 'Advocate G', 2010, {
        DemoCategories.trademark: 3.5,
        DemoCategories.copyright: 3,
      }, 0.50),
      _AdvSpec('a8', 'Advocate H', 2003, {
        DemoCategories.trademark: 5,
        DemoCategories.contract: 4,
        DemoCategories.arbitration: 3,
      }, 0.56),
    ];
    final advocates = [
      for (final s in advocateSpecs)
        Advocate(
          id: s.id,
          displayName: s.name,
          aliases: [
            s.name.replaceAll('Advocate ', 'Adv. '),
            '${s.name} (Demo)',
          ],
          chamber: 'Fictional Chambers ${s.name.split(' ').last}',
          practiceSince: s.since,
          practiceAreas: s.affinity.keys.toList(),
          identityVerification: s.id == 'a7'
              ? VerificationStatus.pendingReview
              : VerificationStatus.verified,
        ),
    ];

    // --- Judgments ----------------------------------------------------------
    const partiesA = [
      'Alpha Foods',
      'Bravo Textiles',
      'Cobalt Pharma',
      'Delta Beverages',
      'Ember Apparel',
      'Fable Media',
      'Granite Tools',
      'Harbor Logistics',
      'Indigo Cosmetics',
      'Juniper Software',
      'Kestrel Motors',
      'Lotus Publishing',
    ];
    const partiesB = [
      'Mango Retail',
      'Nimbus Labs',
      'Orbit Electronics',
      'Pebble Snacks',
      'Quartz Home',
      'Ripple Studios',
      'Saffron Traders',
      'Tundra Gear',
      'Umber Prints',
      'Vertex Devices',
      'Willow Organics',
      'Zephyr Brands',
    ];

    final rng = _Rng(20261114);
    final judgments = <Judgment>[];
    final catWeights = {
      DemoCategories.trademark: 34.0,
      DemoCategories.passingOff: 12.0,
      DemoCategories.copyright: 11.0,
      DemoCategories.patent: 13.0,
      DemoCategories.contract: 14.0,
      DemoCategories.arbitration: 12.0,
    };
    final benchForCategory = <String, List<String>>{
      DemoCategories.trademark: ['j1', 'j3', 'j6'],
      DemoCategories.passingOff: ['j1', 'j3'],
      DemoCategories.copyright: ['j1', 'j6'],
      DemoCategories.patent: ['j5', 'j6'],
      DemoCategories.contract: ['j3', 'j1', 'j7'],
      DemoCategories.arbitration: ['j3', 'j7'],
    };

    for (var n = 1; n <= 170; n++) {
      final cat = rng.weighted(catWeights);
      final stage = rng.weighted({
        CaseStage.interimInjunction: 5.0,
        CaseStage.finalHearing: 2.5,
        CaseStage.appeal: 2.0,
        CaseStage.other: 0.5,
      });
      final daysAgo = 20 + rng.nextInt(365 * 9);
      final date = ref.subtract(Duration(days: daysAgo));
      final bench = stage == CaseStage.appeal
          ? rng.pick(const [
              ['j2', 'j4'],
              ['j2', 'j7'],
            ])
          : [rng.pick(benchForCategory[cat]!)];

      final weightsForCat = {
        for (final s in advocateSpecs) s: (s.affinity[cat] ?? 0.15),
      };
      final pet = rng.weighted(weightsForCat);
      weightsForCat.remove(pet);
      final res = rng.weighted(weightsForCat);

      final interim = stage == CaseStage.interimInjunction;
      final edge = pet.strength - res.strength;
      final roll = rng.next();
      final CaseDisposition disposition;
      if (roll < 0.06) {
        disposition = CaseDisposition.settled;
      } else if (roll < 0.10) {
        disposition = CaseDisposition.withdrawn;
      } else if (roll < 0.13) {
        disposition = CaseDisposition.procedural;
      } else if (roll < 0.16) {
        disposition = CaseDisposition.indeterminate;
      } else if (roll < 0.24 && !interim) {
        disposition = CaseDisposition.partlyAllowed;
      } else {
        final win = rng.next() < (0.5 + edge * 2.6).clamp(0.1, 0.9);
        disposition = interim
            ? (win
                  ? CaseDisposition.interimGranted
                  : CaseDisposition.interimRefused)
            : (win
                  ? CaseDisposition.finalAllowed
                  : CaseDisposition.finalDismissed);
      }

      VerificationStatus verif(_AdvSpec s) {
        if (s.id == 'a7') {
          return rng.chance(0.45)
              ? VerificationStatus.verified
              : VerificationStatus.unverified;
        }
        final r = rng.next();
        if (r < 0.88) return VerificationStatus.verified;
        if (r < 0.95) return VerificationStatus.pendingReview;
        return VerificationStatus.unverified;
      }

      final initSide = switch (stage) {
        CaseStage.appeal => RepresentationSide.appellant,
        _ when cat == DemoCategories.arbitration =>
          RepresentationSide.petitioner,
        _ => RepresentationSide.plaintiff,
      };
      final respSide =
          stage == CaseStage.appeal || cat == DemoCategories.arbitration
          ? RepresentationSide.respondent
          : RepresentationSide.defendant;

      final id = 'J${n.toString().padLeft(3, '0')}';
      final pA = rng.pick(partiesA);
      final pB = rng.pick(partiesB);
      final caseType = switch (stage) {
        CaseStage.appeal => 'FAO(OS)(COMM)',
        _ when cat == DemoCategories.arbitration => 'OMP(I)(COMM)',
        _ => 'CS(COMM)',
      };
      final caseNo = '$caseType ${100 + rng.nextInt(800)}/${date.year}';
      final citation = 'DEMO-DHC-${date.year}-${n.toString().padLeft(4, '0')}';
      final confidence = disposition == CaseDisposition.indeterminate
          ? 0.42 + rng.next() * 0.2
          : 0.72 + rng.next() * 0.27;
      final review = confidence < 0.8
          ? ReviewStatus.awaitingReview
          : (rng.chance(0.4)
                ? ReviewStatus.humanReviewed
                : ReviewStatus.autoAccepted);

      final sources = <JudgmentSourceRef>[];
      final retrieved = ref.subtract(Duration(days: rng.nextInt(40)));
      if (rng.chance(0.72)) {
        sources.add(
          JudgmentSourceRef(
            type: SourceType.vakilaj,
            retrievedAt: retrieved,
            documentVersion: 'v1',
            verification: VerificationStatus.unverified,
            externalId: 'demo-vk-$n',
          ),
        );
      }
      if (sources.isEmpty || rng.chance(0.5)) {
        sources.add(
          JudgmentSourceRef(
            type: SourceType.indianKanoon,
            retrievedAt: retrieved,
            documentVersion: 'v1',
            verification: VerificationStatus.unverified,
            externalId: 'demo-ik-$n',
          ),
        );
      }
      if (rng.chance(0.8)) {
        sources.add(
          JudgmentSourceRef(
            type: SourceType.official,
            retrievedAt: retrieved,
            documentVersion: 'v1',
            verification: VerificationStatus.verified,
            externalId: 'demo-official-$n',
          ),
        );
      }
      final conflict = n % 29 == 0
          ? 'Secondary repository lists a different order date. Official record '
                'used for verification (demo discrepancy).'
          : null;

      final petName = pet.name;
      final resName = res.name;
      final passages = [
        Passage(
          id: '$id-p1',
          paragraph: 'Appearances',
          text:
              '$petName for the ${initSide.label.toLowerCase()}. $resName for the '
              '${respSide.label.toLowerCase()}. [Illustrative text]',
          supports: 'Counsel appearances and representation sides',
        ),
        Passage(
          id: '$id-p2',
          paragraph: 'Para ${8 + rng.nextInt(20)}',
          text: _findingText(cat, disposition),
          supports: 'Relevance to ${cat.toLowerCase()}',
        ),
        Passage(
          id: '$id-p3',
          paragraph: 'Para ${30 + rng.nextInt(20)}',
          text: _operativeText(disposition),
          supports: 'Outcome classification: ${disposition.label}',
        ),
      ];

      judgments.add(
        Judgment(
          id: id,
          title: '$pA (Demo) v. $pB (Demo)',
          citation: citation,
          caseNumber: caseNo,
          courtId: 'dhc',
          benchJudgeIds: bench,
          date: date,
          category: cat,
          statutes: DemoCategories.statutes[cat]!,
          stage: stage,
          disposition: disposition,
          dispositionConfidence: double.parse(confidence.toStringAsFixed(2)),
          reviewStatus: review,
          appearances: [
            Appearance(
              advocateId: pet.id,
              side: initSide,
              role: rng.chance(0.3) ? CounselRole.senior : CounselRole.arguing,
              verification: verif(pet),
              confidence: 0.8 + rng.next() * 0.19,
              supportingPassageId: '$id-p1',
            ),
            Appearance(
              advocateId: res.id,
              side: respSide,
              role: rng.chance(0.3) ? CounselRole.senior : CounselRole.arguing,
              verification: verif(res),
              confidence: 0.8 + rng.next() * 0.19,
              supportingPassageId: '$id-p1',
            ),
          ],
          sources: sources,
          passages: passages,
          summary:
              'Illustrative ${stage.label.toLowerCase()} matter concerning '
              '${cat.toLowerCase()}. Generated for the prototype; not a real case.',
          conflictNote: conflict,
        ),
      );
    }
    judgments.sort((a, b) => b.date.compareTo(a.date));

    return DemoDataset._(
      courts: courts,
      judges: judges,
      rosters: {
        'dhc': CourtRoster(current: v12, history: [v11]),
      },
      listings: listings,
      sittingNotices: notices,
      advocates: advocates,
      judgments: judgments,
      mentionOnlyCounts: const {'a1': 6, 'a2': 4, 'a3': 3, 'a7': 19, 'a8': 2},
    );
  }

  static String _findingText(String cat, CaseDisposition d) =>
      'The court considered whether the ${cat.toLowerCase()} claim met the '
      'applicable threshold, including prima facie case, balance of '
      'convenience and irreparable harm where relevant. [Illustrative text]';

  static String _operativeText(CaseDisposition d) => switch (d) {
    CaseDisposition.finalAllowed =>
      'The suit is decreed in terms of the prayer clause. [Illustrative text]',
    CaseDisposition.finalDismissed =>
      'The suit is dismissed. No order as to costs. [Illustrative text]',
    CaseDisposition.partlyAllowed => 'The claim is allowed in part, limited to the reliefs set out above. [Illustrative text]',
    CaseDisposition.interimGranted => 'Pending the suit, the defendant is restrained as prayed. [Illustrative text]',
    CaseDisposition.interimRefused => 'The application for interim injunction is dismissed. [Illustrative text]',
    CaseDisposition.settled => 'The parties have settled; the matter is disposed of in terms of the settlement. [Illustrative text]',
    CaseDisposition.withdrawn =>
      'Dismissed as withdrawn with liberty. [Illustrative text]',
    CaseDisposition.procedural => 'Transferred to the appropriate bench; no findings on merits. [Illustrative text]',
    CaseDisposition.indeterminate =>
      'List for further directions. [Illustrative text]',
  };
}

class _AdvSpec {
  const _AdvSpec(this.id, this.name, this.since, this.affinity, this.strength);
  final String id;
  final String name;
  final int since;
  final Map<String, double> affinity;
  final double strength;
}
