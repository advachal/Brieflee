/// Plain-language subject areas mapped to Delhi High Court case types.
///
/// The case type is set by the court registry, so this is a reliable way to
/// answer "arbitration", "bail" or "trademark" questions from metadata alone.
/// It is a lookup, not a classifier: a matter is only placed in a subject when
/// its official case type belongs to it.
class SubjectArea {
  const SubjectArea({
    required this.id,
    required this.label,
    required this.keywords,
    required this.matches,
  });

  final String id;
  final String label;

  /// Words or phrases (lower case) in a question that select this subject.
  final List<String> keywords;

  /// Returns true when an official case type belongs to this subject.
  final bool Function(String caseType) matches;
}

String _n(String t) => t.toUpperCase().replaceAll(' ', '');

final subjectAreas = <SubjectArea>[
  SubjectArea(
    id: 'arbitration',
    label: 'Arbitration',
    keywords: [
      'arbitration',
      'arbitral',
      'arbitrator',
      'award',
      'section 9',
      'section 11',
      'section 34',
      'section 37',
    ],
    matches: (t) =>
        _n(t).startsWith('ARB') ||
        _n(t).startsWith('O.M.P') ||
        _n(t).startsWith('OMP'),
  ),
  SubjectArea(
    id: 'ip',
    label: 'Intellectual property',
    keywords: [
      'trademark',
      'trade mark',
      'patent',
      'copyright',
      'design',
      'intellectual property',
      'ipd',
      'infringement',
      'passing off',
      'brand',
    ],
    matches: (t) => _n(t).contains('IPD') || _n(t) == 'I.P.A.',
  ),
  SubjectArea(
    id: 'commercial',
    label: 'Commercial disputes',
    keywords: [
      'commercial',
      'contract',
      'breach',
      'recovery',
      'suit',
      'damages',
      'injunction',
      'business',
    ],
    matches: (t) => _n(t).contains('COMM'),
  ),
  SubjectArea(
    id: 'bail',
    label: 'Bail',
    keywords: ['bail', 'anticipatory', 'custody', 'arrest'],
    matches: (t) => _n(t).startsWith('BAIL'),
  ),
  SubjectArea(
    id: 'quashing',
    label: 'Quashing and criminal petitions',
    keywords: [
      'quash',
      'quashing',
      'fir',
      '482',
      '528',
      'bnss',
      'criminal complaint',
      'summoning',
    ],
    matches: (t) => _n(t) == 'CRL.M.C.',
  ),
  SubjectArea(
    id: 'criminal_appeal',
    label: 'Criminal appeals and revisions',
    keywords: [
      'criminal appeal',
      'conviction',
      'acquittal',
      'sentence',
      'revision',
      'murder',
      'ipc',
      'bns',
      'pocso',
    ],
    matches: (t) =>
        _n(t).startsWith('CRL.A') ||
        _n(t).startsWith('CRL.REV') ||
        _n(t).startsWith('CRL.L.P') ||
        _n(t).startsWith('DEATH'),
  ),
  SubjectArea(
    id: 'ndps',
    label: 'Narcotics (NDPS)',
    keywords: ['ndps', 'narcotic', 'drugs', 'contraband'],
    matches: (t) => _n(t).contains('NDPS'),
  ),
  SubjectArea(
    id: 'cheque',
    label: 'Cheque bounce (NI Act)',
    keywords: [
      'cheque',
      'check bounce',
      '138',
      'negotiable instruments',
      'ni act',
      'dishonour',
    ],
    matches: (t) => _n(t).contains('(NI)'),
  ),
  SubjectArea(
    id: 'service',
    label: 'Service law',
    keywords: [
      'service matter',
      'regularisation',
      'regularization',
      'regularise',
      'regularize',
      'seniority',
      'promotion',
      'pay scale',
      'recruitment',
      'public service commission',
      'pension',
      'termination',
      'transfer',
      'employee',
      'employees',
      'ad hoc',
      'adhoc',
      'umadevi',
    ],
    matches: (t) =>
        _n(t) == 'W.P.(C)' || _n(t) == 'LPA' || _n(t).startsWith('CWP'),
  ),
  SubjectArea(
    id: 'writ',
    label: 'Writs and public law',
    keywords: [
      'writ',
      'constitutional',
      'article 226',
      'public law',
      'mandamus',
      'certiorari',
      'education',
      'admission',
    ],
    matches: (t) =>
        _n(t) == 'W.P.(C)' || _n(t) == 'LPA' || _n(t).startsWith('CWP'),
  ),
  SubjectArea(
    id: 'habeas',
    label: 'Criminal writs and habeas corpus',
    keywords: ['habeas', 'habeas corpus', 'parole', 'furlough', 'detention'],
    matches: (t) => _n(t) == 'W.P.(CRL)',
  ),
  SubjectArea(
    id: 'matrimonial',
    label: 'Family and matrimonial',
    keywords: [
      'divorce',
      'matrimonial',
      'maintenance',
      'custody of child',
      'family court',
      'marriage',
      'dowry',
      'wife',
      'husband',
    ],
    matches: (t) => _n(t).contains('MAT'),
  ),
  SubjectArea(
    id: 'motor_accident',
    label: 'Motor accident claims',
    keywords: [
      'motor accident',
      'accident',
      'mact',
      'compensation claim',
      'insurance claim',
    ],
    matches: (t) => _n(t).startsWith('MAC'),
  ),
  SubjectArea(
    id: 'tax',
    label: 'Tax, customs and excise',
    keywords: [
      'tax',
      'income tax',
      'gst',
      'customs',
      'excise',
      'vat',
      'service tax',
      'assessment',
    ],
    matches: (t) => const {
      'ITA',
      'SERTA',
      'CUSAA',
      'VATAPPEAL',
      'ST.APPL.',
      'CEAC',
      'CUS.A.C.',
    }.contains(_n(t)),
  ),
  SubjectArea(
    id: 'rent',
    label: 'Rent and tenancy',
    keywords: ['rent', 'tenant', 'tenancy', 'eviction', 'landlord'],
    matches: (t) => _n(t).startsWith('RC.'),
  ),
  SubjectArea(
    id: 'company',
    label: 'Company law and insolvency',
    keywords: [
      'company',
      'winding up',
      'insolvency',
      'liquidation',
      'companies act',
    ],
    matches: (t) =>
        _n(t).startsWith('CO.') ||
        _n(t).startsWith('CCP(CO') ||
        _n(t).startsWith('CRL.O.(CO') ||
        _n(t).startsWith('CRL.M.(CO'),
  ),
  SubjectArea(
    id: 'civil_appeal',
    label: 'Civil appeals and revisions',
    keywords: [
      'civil appeal',
      'first appeal',
      'second appeal',
      'decree',
      'property',
      'partition',
      'possession',
      'civil revision',
    ],
    matches: (t) =>
        _n(t).startsWith('RFA') ||
        _n(t).startsWith('FAO') ||
        _n(t) == 'RSA' ||
        _n(t) == 'C.R.P.' ||
        _n(t).startsWith('CM(M)'),
  ),
  SubjectArea(
    id: 'execution',
    label: 'Execution',
    keywords: ['execution', 'enforcement', 'decree holder'],
    matches: (t) =>
        _n(t).startsWith('EX') ||
        _n(t).startsWith('EFA') ||
        _n(t).contains('ENF'),
  ),
  SubjectArea(
    id: 'contempt',
    label: 'Contempt',
    keywords: ['contempt'],
    matches: (t) => _n(t).startsWith('CONT'),
  ),
  SubjectArea(
    id: 'pmla',
    label: 'Money laundering (PMLA)',
    keywords: ['pmla', 'money laundering', 'enforcement directorate'],
    matches: (t) => _n(t).contains('PMLA'),
  ),
  SubjectArea(
    id: 'land',
    label: 'Land acquisition',
    keywords: ['land acquisition'],
    matches: (t) => _n(t).startsWith('LA.'),
  ),
  SubjectArea(
    id: 'rera',
    label: 'Real estate (RERA)',
    keywords: ['rera', 'real estate', 'builder', 'homebuyer', 'flat buyer'],
    matches: (t) => _n(t).contains('RERA'),
  ),
  SubjectArea(
    id: 'probate',
    label: 'Probate and succession',
    keywords: ['probate', 'succession', 'will', 'letters of administration'],
    matches: (t) => _n(t).startsWith('TEST'),
  ),
  SubjectArea(
    id: 'election',
    label: 'Election petitions',
    keywords: ['election petition'],
    matches: (t) => _n(t).startsWith('EL.PET'),
  ),
];
