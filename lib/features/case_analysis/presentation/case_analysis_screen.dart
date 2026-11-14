import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/api/brieflee_api.dart';
import '../../../core/mock/demo_dataset.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/status_badges.dart';
import '../../advocate_search/application/recommendation_providers.dart';
import '../../case_intake/application/matter_providers.dart';
import '../../court_explorer/application/court_providers.dart';
import '../../judge_roster/presentation/bench_intelligence_card.dart';

class CaseAnalysisScreen extends ConsumerStatefulWidget {
  const CaseAnalysisScreen({super.key, required this.matterId});
  final String matterId;

  @override
  ConsumerState<CaseAnalysisScreen> createState() => _CaseAnalysisScreenState();
}

class _CaseAnalysisScreenState extends ConsumerState<CaseAnalysisScreen> {
  StreamSubscription<Job>? _sub;
  Job? _job;
  CaseAnalysis? _draft;
  Matter? _matter;
  Set<String> _manualBench = {};
  CaseListing? _listing;
  Object? _error;

  // Matching progress
  Job? _matchJob;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await ref.read(matterRepositoryProvider).get(widget.matterId);
      if (!mounted) return;
      setState(() {
        _matter = m;
        _draft = m.analysis;
      });
      if (m.analysis == null) _runAnalysis();
    } catch (e) {
      setState(() => _error = e);
    }
  }

  void _runAnalysis() {
    _sub?.cancel();
    _sub = ref.read(matterRepositoryProvider).analyze(widget.matterId).listen((
      job,
    ) async {
      setState(() => _job = job);
      if (job.status == JobStatus.succeeded) {
        final m = await ref.read(matterRepositoryProvider).get(widget.matterId);
        refreshMatters(ref, widget.matterId);
        if (mounted) {
          setState(() {
            _matter = m;
            _draft = m.analysis;
          });
        }
      }
    }, onError: (Object e) => setState(() => _error = e));
  }

  void _edit(CaseAnalysis next) => setState(() => _draft = next);

  List<String> get _benchIds {
    if (_manualBench.isNotEmpty) return _manualBench.toList();
    final l = _listing;
    if (l != null && l.status != ListingStatus.notFound) return l.benchJudgeIds;
    return const [];
  }

  Future<void> _findAdvocates() async {
    final draft = _draft;
    if (draft == null) return;
    final matterRepo = ref.read(matterRepositoryProvider);
    await matterRepo.saveAnalysis(widget.matterId, draft);
    final weights = ref.read(scoringWeightsProvider);
    final stream = ref
        .read(recommendationRepositoryProvider)
        .start(
          StartRecommendationRequest(
            matterId: widget.matterId,
            analysis: draft,
            filters: SearchFilters(courtId: draft.courtId),
            methodologyVersion: weights.methodologyVersion,
          ),
          benchJudgeIds: _benchIds,
        );
    await for (final job in stream) {
      if (!mounted) return;
      setState(() => _matchJob = job);
      if (job.status == JobStatus.succeeded && job.resultId != null) {
        await matterRepo.attachRecommendation(widget.matterId, job.resultId!);
        refreshMatters(ref, widget.matterId);
        if (mounted) context.go(Routes.results(job.resultId!));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorView(
        error: _error!,
        onRetry: () {
          setState(() => _error = null);
          _load();
        },
      );
    }
    final m = _matter;
    if (m == null) return const LoadingView();
    final draft = _draft;

    if (draft == null) {
      final job = _job;
      return PageBody(
        maxWidth: 640,
        children: [
          PageHeader(title: 'Analyzing your matter', subtitle: m.title),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: job?.progress,
                  minHeight: 6,
                  color: AppColors.teal,
                  backgroundColor: AppColors.border,
                ),
                const SizedBox(height: 14),
                Text(
                  job?.step ?? 'Starting…',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Job ${job?.id ?? '…'} · polling for progress',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final matching = _matchJob != null && !_matchJob!.isDone;
    final courts = ref.watch(courtsProvider);

    return PageBody(
      maxWidth: 900,
      children: [
        PageHeader(
          title: 'Case analysis',
          subtitle: 'Review and correct what we extracted. Nothing is searched until you continue.',
          actions: [
            Pill(
              label: draft.analyzerLabel,
              color: AppColors.mixed,
              icon: Icons.rule,
              tooltip: 'Rule-based stand-in for the AI analysis service',
            ),
          ],
        ),
        SectionCard(
          title: m.title,
          subtitle: m.description.isEmpty ? null : m.description,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(label: m.intakeMode.label, color: AppColors.navy),
              if (m.caseNumber != null)
                Pill(
                  label: m.caseNumber!,
                  color: AppColors.navy,
                  icon: Icons.tag,
                ),
              for (final d in m.documents)
                Pill(
                  label: d.fileName,
                  color: AppColors.teal,
                  icon: Icons.attach_file,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Extracted details',
          subtitle: 'Fields marked "inferred" come from automated extraction. Edit anything.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'Court',
                field: 'court',
                draft: draft,
                child: courts.when(
                  data: (list) => DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: draft.courtId,
                    items: [
                      for (final c in list)
                        DropdownMenuItem(
                          value: c.id,
                          enabled: c.support == CourtSupport.pilot,
                          child: Text(
                            c.support == CourtSupport.pilot
                                ? c.name
                                : '${c.name} (planned)',
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        _edit(draft.copyWith(courtId: v, editedField: 'court')),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
              ),
              _Field(
                label: 'Case category',
                field: 'category',
                draft: draft,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: draft.caseCategory,
                  items: [
                    for (final c in DemoCategories.all)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => _edit(
                    draft.copyWith(caseCategory: v, editedField: 'category'),
                  ),
                ),
              ),
              _Field(
                label: 'Stage of proceedings',
                field: 'stage',
                draft: draft,
                child: DropdownButtonFormField<CaseStage>(
                  isExpanded: true,
                  initialValue: draft.stage,
                  items: [
                    for (final s in CaseStage.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) =>
                      _edit(draft.copyWith(stage: v, editedField: 'stage')),
                ),
              ),
              _Field(
                label: 'Legal issues',
                field: 'issues',
                draft: draft,
                child: _ChipListEditor(
                  values: draft.legalIssues,
                  hint: 'Add an issue',
                  onChanged: (v) => _edit(
                    draft.copyWith(legalIssues: v, editedField: 'issues'),
                  ),
                ),
              ),
              _Field(
                label: 'Statutes',
                field: 'statutes',
                draft: draft,
                child: _ChipListEditor(
                  values: draft.statutes,
                  hint: 'Add a statute or provision',
                  onChanged: (v) => _edit(
                    draft.copyWith(statutes: v, editedField: 'statutes'),
                  ),
                ),
              ),
              _Field(
                label: 'Relief sought',
                field: 'relief',
                draft: draft,
                child: TextFormField(
                  initialValue: draft.reliefSought,
                  onChanged: (v) => _draft = _draft!.copyWith(
                    reliefSought: v,
                    editedField: 'relief',
                  ),
                ),
              ),
              _Field(
                label: 'Parties',
                field: 'parties',
                draft: draft,
                child: TextFormField(
                  initialValue: draft.parties,
                  onChanged: (v) => _draft = _draft!.copyWith(
                    parties: v,
                    editedField: 'parties',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (draft.courtId != null)
          BenchIntelligenceCard(
            courtId: draft.courtId!,
            caseNumber: m.caseNumber,
            manualJudgeIds: _manualBench,
            onManualChanged: (s) => setState(() => _manualBench = s),
            onListingResolved: (l) {
              if (_listing?.caseNumber != l.caseNumber) {
                setState(() => _listing = l);
              }
            },
          ),
        const SizedBox(height: 18),
        if (_matchJob != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: _matchJob!.progress,
                  color: AppColors.teal,
                  backgroundColor: AppColors.border,
                ),
                const SizedBox(height: 6),
                Text(
                  _matchJob!.step,
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: matching ? null : _runAnalysis,
              icon: const Icon(Icons.refresh),
              label: const Text('Re-run extraction'),
            ),
            FilledButton.icon(
              onPressed: matching ? null : _findAdvocates,
              icon: const Icon(Icons.person_search),
              label: const Text('Find advocates'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.field,
    required this.draft,
    required this.child,
  });
  final String label;
  final String field;
  final CaseAnalysis draft;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final edited = draft.userEdited.contains(field);
    final conf = draft.confidence[field];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(width: 8),
              if (edited)
                const Pill(
                  label: 'Edited by you',
                  color: AppColors.teal,
                  icon: Icons.check,
                )
              else if (conf != null)
                Pill(
                  label: 'Inferred · ${(conf * 100).round()}%',
                  color: conf >= 0.75 ? AppColors.navy : AppColors.mixed,
                  tooltip: conf >= 0.75
                      ? 'Extraction confidence'
                      : 'Low confidence: please check this field',
                ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ChipListEditor extends StatefulWidget {
  const _ChipListEditor({
    required this.values,
    required this.onChanged,
    required this.hint,
  });
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String hint;

  @override
  State<_ChipListEditor> createState() => _ChipListEditorState();
}

class _ChipListEditorState extends State<_ChipListEditor> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _add() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    widget.onChanged([...widget.values, v]);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final v in widget.values)
            InputChip(
              label: Text(v),
              onDeleted: () =>
                  widget.onChanged(widget.values.where((x) => x != v).toList()),
            ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _c,
        onSubmitted: (_) => _add(),
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _add),
        ),
      ),
    ],
  );
}
