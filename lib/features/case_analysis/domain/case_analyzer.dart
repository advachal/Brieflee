import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';

/// Turns a matter into structured, editable case details.
///
/// Production: an LLM with structured outputs and evidence validation,
/// after redaction. This milestone ships [RuleBasedDemoAnalyzer], a
/// keyword matcher that is clearly labelled as a stand-in.
abstract interface class CaseAnalyzer {
  CaseAnalysis analyze(Matter matter);
}

class RuleBasedDemoAnalyzer implements CaseAnalyzer {
  const RuleBasedDemoAnalyzer();

  static const label = 'Demo keyword extractor (not AI)';

  @override
  CaseAnalysis analyze(Matter matter) {
    final text = [
      matter.description,
      matter.caseNumber ?? '',
      ...matter.documents.map((d) => d.fileName),
    ].join(' ').toLowerCase();

    bool has(List<String> words) => words.any(text.contains);

    var category = DemoCategories.trademark;
    var catConf = 0.55;
    if (has(['patent', 'invention', 'claim construction'])) {
      category = DemoCategories.patent;
      catConf = 0.82;
    } else if (has(['arbitration', 'section 9', 's.9', 'omp(i)', 'arbitral'])) {
      category = DemoCategories.arbitration;
      catConf = 0.84;
    } else if (has([
      'copyright',
      'film',
      'music',
      'software code',
      'literary',
    ])) {
      category = DemoCategories.copyright;
      catConf = 0.8;
    } else if (has(['passing off', 'get-up', 'trade dress'])) {
      category = DemoCategories.passingOff;
      catConf = 0.78;
    } else if (has([
      'trademark',
      'trade mark',
      'brand',
      'logo',
      'deceptively similar',
      'mark',
    ])) {
      category = DemoCategories.trademark;
      catConf = 0.86;
    } else if (has([
      'contract',
      'breach',
      'invoice',
      'supply agreement',
      'damages',
    ])) {
      category = DemoCategories.contract;
      catConf = 0.74;
    }

    var stage = CaseStage.interimInjunction;
    var stageConf = 0.5;
    if (has(['appeal', 'fao', 'appellate'])) {
      stage = CaseStage.appeal;
      stageConf = 0.8;
    } else if (has([
      'injunction',
      'restrain',
      'interim',
      'ex parte',
      'urgent',
    ])) {
      stage = CaseStage.interimInjunction;
      stageConf = 0.83;
    } else if (has(['final hearing', 'trial', 'evidence', 'decree'])) {
      stage = CaseStage.finalHearing;
      stageConf = 0.7;
    }

    final issues = <String>[
      if (category == DemoCategories.trademark) ...[
        'Likelihood of confusion between marks',
        'Prima facie case for infringement',
      ],
      if (category == DemoCategories.passingOff)
        'Goodwill and misrepresentation',
      if (category == DemoCategories.copyright)
        'Substantial similarity of copied work',
      if (category == DemoCategories.patent)
        'Validity and infringement of patent claims',
      if (category == DemoCategories.contract)
        'Breach of contract and quantum of damages',
      if (category == DemoCategories.arbitration)
        'Interim protection pending arbitration',
      if (stage == CaseStage.interimInjunction)
        'Balance of convenience and irreparable harm',
    ];

    final relief = switch (stage) {
      CaseStage.interimInjunction =>
        'Interim injunction restraining the opposite party',
      CaseStage.appeal => 'Setting aside of the impugned order',
      CaseStage.finalHearing => 'Permanent injunction and damages',
      _ => 'To be confirmed',
    };

    final courtId =
        matter.courtId ??
        (has(['delhi', 'dhc', 'cs(comm)', 'fao(os)', 'omp(i)'])
            ? 'dhc'
            : 'dhc');

    return CaseAnalysis(
      courtId: courtId,
      caseCategory: category,
      legalIssues: issues,
      statutes: DemoCategories.statutes[category]!.take(2).toList(),
      reliefSought: relief,
      stage: stage,
      parties: 'Not identified: please add the parties',
      caseNumber: matter.caseNumber,
      confidence: {
        'court': matter.courtId != null ? 0.95 : 0.6,
        'category': catConf,
        'stage': stageConf,
        'statutes': 0.62,
        'relief': 0.58,
        'parties': 0.1,
      },
      analyzerLabel: label,
    );
  }
}
