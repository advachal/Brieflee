import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_colors.dart';
import '../models/models.dart';

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.color,
    this.background,
    this.icon,
    this.tooltip,
  });

  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Marks content as fictional demo data.
class IllustrativeTag extends StatelessWidget {
  const IllustrativeTag({super.key, this.label = 'Illustrative'});
  final String label;

  @override
  Widget build(BuildContext context) => Pill(
    label: label,
    color: const Color(0xFF8A6A1F),
    background: AppColors.goldSoft,
    icon: Icons.science_outlined,
    tooltip: 'Fictional demo data. Not a real advocate, judge or case.',
  );
}

class VerificationBadge extends StatelessWidget {
  const VerificationBadge(this.status, {super.key, this.compact = false});
  final VerificationStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      VerificationStatus.verified => (
        AppColors.favorable,
        Icons.verified_outlined,
      ),
      VerificationStatus.unverified => (AppColors.neutral, Icons.help_outline),
      VerificationStatus.conflicting => (
        AppColors.unfavorable,
        Icons.report_gmailerrorred,
      ),
      VerificationStatus.pendingReview => (
        AppColors.mixed,
        Icons.hourglass_top,
      ),
    };
    return Pill(
      label: compact ? status.label.split(' ').first : status.label,
      color: color,
      icon: icon,
      tooltip: status.label,
    );
  }
}

class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge(this.outcome, {super.key});
  final PartyOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final color = switch (outcome) {
      PartyOutcome.favorable => AppColors.favorable,
      PartyOutcome.unfavorable => AppColors.unfavorable,
      PartyOutcome.mixed => AppColors.mixed,
      PartyOutcome.excluded => AppColors.neutral,
    };
    return Pill(label: outcome.label, color: color);
  }
}

class ReliabilityBadge extends StatelessWidget {
  const ReliabilityBadge(this.reliability, {super.key});
  final EvidenceReliability reliability;

  @override
  Widget build(BuildContext context) {
    final color = switch (reliability) {
      EvidenceReliability.high => AppColors.favorable,
      EvidenceReliability.moderate => AppColors.teal,
      EvidenceReliability.low => AppColors.mixed,
      EvidenceReliability.insufficient => AppColors.neutral,
    };
    return Pill(
      label: 'Evidence: ${reliability.label}',
      color: color,
      icon: Icons.fact_check_outlined,
      tooltip:
          'Evidence reliability is shown separately from match relevance. '
          'It reflects sample size and verified counsel roles.',
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge(this.source, {super.key, this.verification});
  final SourceType source;
  final VerificationStatus? verification;

  @override
  Widget build(BuildContext context) {
    final color = switch (source) {
      SourceType.vakilaj => AppColors.navy,
      SourceType.indianKanoon => AppColors.teal,
      SourceType.official => AppColors.favorable,
      SourceType.userUpload => AppColors.neutral,
    };
    return Pill(
      label: source.label,
      color: color,
      icon: source == SourceType.official
          ? Icons.account_balance_outlined
          : Icons.storage_outlined,
      tooltip:
          '${source.role}${verification == null ? '' : ' · ${verification!.label}'}',
    );
  }
}
