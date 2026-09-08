import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/date_format.dart';

/// One step of the customer-facing application timeline.
///
/// The web app tracks a project across several collections (lead ->
/// project -> liaising). A customer does not care about that split, so it
/// arrives here as a single ordered list of milestones.
///
/// NAMED BY THE SERVER. These labels are the office's own pipeline columns, and
/// those live in editable masters — a sales team can add "Awaiting Sanction"
/// this afternoon. The app deliberately holds no list of its own; it renders
/// what `Enersol Customer Portal` composes, which is the only place that can
/// read the masters and know their order.
class AppStage {
  const AppStage({
    required this.label,
    required this.state,
    this.date,
    this.note,
    this.group = '',
    this.key = '',
  });

  final String label;
  final StageState state;
  final DateTime? date;
  final String? note;

  /// Which half of the journey this step belongs to — "Enquiry", "Project",
  /// "Approvals". Used as a heading so a long timeline reads as phases rather
  /// than as one undifferentiated ladder.
  final String group;

  /// The client-application step this milestone IS, when it is one.
  ///
  /// Only the approval steps carry it — the sales and delivery pipelines are
  /// columns on the office's board, not steps with their own paperwork. It is
  /// what lets an outstanding document request be shown against the milestone
  /// it is actually holding up rather than in a list of its own.
  final String key;

  static StageState stateFrom(String raw) => switch (raw) {
        'done' => StageState.done,
        'current' => StageState.current,
        _ => StageState.pending,
      };
}

enum StageState { done, current, pending }

/// A solar installation application, as the customer sees it.
class SolarApplication {
  const SolarApplication({
    required this.reference,
    required this.status,
    required this.capacityKw,
    required this.submittedOn,
    required this.stages,
    this.stage = '',
    this.leadId,
    this.projectId,
    this.projectName,
    this.siteAddress,
    this.expectedCompletion,
    this.discom,
    this.projectType,
    this.isConfirmed = false,
  });

  final String reference;
  final String status;

  /// The office's own name for where this job is right now — the pipeline
  /// column, not the lifecycle enum. This is the word the customer and the
  /// salesperson on the phone need to be using for the same thing.
  final String stage;

  final double capacityKw;
  final DateTime submittedOn;
  final List<AppStage> stages;

  final String? leadId;
  final String? projectId;
  final String? projectName;
  final String? siteAddress;
  final DateTime? expectedCompletion;
  final String? discom;
  final String? projectType;
  /// True once this application has become a project.
  final bool isConfirmed;

  /// Fraction of milestones already cleared, for the progress bar.
  ///
  /// The step IN FLIGHT counts as half. Without it a job sitting in the first
  /// column of a fresh pipeline reads as 0% — "nothing has happened" — when the
  /// truth is that it has started and is being worked on.
  double get progress {
    if (stages.isEmpty) return 0;
    final done = stages.where((s) => s.state == StageState.done).length;
    final inFlight = stages.where((s) => s.state == StageState.current).length;
    return ((done + inFlight * 0.5) / stages.length).clamp(0, 1);
  }

  /// The stage in flight right now, for a one-line "what's happening". Falls
  /// back to the server's own headline when no step is marked current.
  AppStage? get currentStage {
    for (final s in stages) {
      if (s.state == StageState.current) return s;
    }
    return null;
  }

  /// What to print under "Now:" — the live step, or the headline stage.
  String get currentLabel {
    final s = currentStage?.label.trim() ?? '';
    if (s.isNotEmpty) return s;
    return stage.trim().isNotEmpty ? stage.trim() : status;
  }

  int get completedCount => stages.where((s) => s.state == StageState.done).length;

  /// For a confirmed job `status` now carries the office's board column, the
  /// same value as [stage] — the separate execution status it used to hold was
  /// retired and stopped moving, so serving it would have shown a commissioned
  /// job as "Pending". Enquiries still send their own lifecycle here, which is
  /// why 'won' and 'lost' stay in the arms below.
  LinearGradient get statusGradient => switch (status.toLowerCase()) {
        'handover' || 'completed' || 'closed' => AppColors.leaf,
        'cancelled' || 'rejected' || 'lost' => AppColors.rose,
        'on hold' => AppColors.violet,
        'installation' || 'commissioning' || 'in progress' || 'won' => AppColors.brand,
        _ => AppColors.sky,
      };
}

/// A downloadable file attached to a completed installation.
class CustomerDocument {
  const CustomerDocument({
    required this.title,
    required this.category,
    required this.issuedOn,
    this.url,
    this.fileName,
    this.sizeLabel,
    this.validUntil,
  });

  final String title;

  /// Free-text grouping shown as the section header, e.g. "Panel Warranty".
  final String category;
  final DateTime issuedOn;

  /// Always ABSOLUTE by the time it reaches here — see the repository. The OS is
  /// handed this string to open, and it has no idea what host the app talks to.
  final String? url;

  /// What the file was called when it was uploaded (`warranty.pdf`), for the
  /// download sheet. Absent on an old row, or a pasted link.
  final String? fileName;
  final String? sizeLabel;

  /// Warranty cards carry an expiry; government papers usually do not.
  final DateTime? validUntil;

  bool get isDownloadable => url != null && url!.isNotEmpty;
}

/// A single entry in a service request's conversation/log.
class ServiceLog {
  const ServiceLog({
    required this.at,
    required this.by,
    required this.note,
  });

  final DateTime at;
  final String by;
  final String note;
}

class ServiceRequest {
  const ServiceRequest({
    required this.reference,
    required this.type,
    required this.description,
    required this.status,
    required this.raisedOn,
    this.logs = const [],
    this.closedOn,
  });

  final String reference;
  final String type;
  final String description;
  final String status;
  final DateTime raisedOn;
  final List<ServiceLog> logs;
  final DateTime? closedOn;

  bool get isOpen => closedOn == null;

  LinearGradient get statusGradient => switch (status.toLowerCase()) {
        'resolved' || 'closed' => AppColors.leaf,
        'in progress' => AppColors.brand,
        'cancelled' => AppColors.rose,
        _ => AppColors.sky,
      };
}

/// Types a customer may raise a service request under.
const kServiceTypes = <String>[
  'Panel cleaning',
  'Inverter fault',
  'Low generation',
  'Meter issue',
  'Physical damage',
  'Other',
];

/// One person the customer has referred.
class Referral {
  const Referral({
    required this.name,
    required this.status,
    required this.referredOn,
    required this.pointsEarned,
  });

  final String name;
  final String status;
  final DateTime referredOn;
  final int pointsEarned;

  LinearGradient get statusGradient => switch (status.toLowerCase()) {
        'installed' => AppColors.leaf,
        'in progress' => AppColors.brand,
        'lost' => AppColors.rose,
        _ => AppColors.sky,
      };
}

class ReferralSummary {
  const ReferralSummary({
    required this.code,
    required this.totalPoints,
    required this.referrals,
    this.pointsOnInstall = 0,
  });

  final String code;
  final int totalPoints;
  final List<Referral> referrals;

  /// What one referral is worth once it is installed, as the SERVER defines it.
  ///
  /// The figure lives in `Constants.referralPointsOnInstall` and is shipped with
  /// the rows, so the screen can say what a referral still in flight will pay
  /// without keeping its own copy that drifts the day the office changes it.
  /// Zero means the server named no figure, and the screen promises nothing.
  final int pointsOnInstall;

  int get convertedCount =>
      referrals.where((r) => r.status.toLowerCase() == 'installed').length;

  /// Referrals still on their way to a reward.
  ///
  /// A lost job is not waiting on anything, so it is excluded alongside the
  /// installed ones — otherwise "3 pending" counts a referral that will never
  /// pay and the customer waits for points that are not coming.
  int get pendingCount => referrals.where((r) {
        final s = r.status.toLowerCase();
        return s != 'installed' && s != 'lost';
      }).length;

  /// Points the referrals in flight would pay if every one of them installed.
  int get pendingPoints => pendingCount * pointsOnInstall;
}

/// A single day's generation reading.
class GenerationPoint {
  const GenerationPoint({required this.day, required this.kwh});

  final DateTime day;
  final double kwh;
}

class GenerationSummary {
  const GenerationSummary({
    required this.todayKwh,
    required this.monthKwh,
    required this.lifetimeKwh,
    required this.currentKw,
    required this.capacityKw,
    required this.last7Days,
    required this.lastSyncedAt,
  });

  final double todayKwh;
  final double monthKwh;
  final double lifetimeKwh;

  /// Instantaneous output right now.
  final double currentKw;
  final double capacityKw;
  final List<GenerationPoint> last7Days;
  final DateTime lastSyncedAt;

  /// Rough environmental equivalents, the numbers customers actually enjoy.
  double get co2SavedKg => lifetimeKwh * 0.71;
  double get treesEquivalent => co2SavedKg / 21.77;

  /// How hard the array is working right now, 0..1.
  double get utilisation =>
      capacityKw <= 0 ? 0 : (currentKw / capacityKw).clamp(0, 1);
}


/// One file answering a document request, from either side.
class RequestedFile {
  const RequestedFile({
    required this.name,
    required this.url,
    this.thumbUrl,
    this.size = 0,
    this.source = 'staff',
    this.uploadedAt,
  });

  final String name;
  final String url;
  final String? thumbUrl;
  final int size;

  /// 'customer' | 'staff' — who actually produced it.
  final String source;
  final DateTime? uploadedAt;

  bool get fromCustomer => source == 'customer';
}

/// A paper the office is waiting on FROM this customer.
///
/// The mirror image of [CustomerDocument]: that one is what we gave them and is
/// finished the moment it exists, this is what we want back and is only
/// finished when they send it. Kept a separate type for the same reason the
/// collections are separate — this one has a deadline, a status and something
/// the customer is expected to DO.
class DocumentRequest {
  const DocumentRequest({
    required this.id,
    required this.title,
    required this.status,
    this.number = '',
    this.description = '',
    this.category = '',
    this.projectId = '',
    this.projectName = '',
    this.stepKey = '',
    this.stepName = '',
    this.priority = 'Normal',
    this.mandatory = true,
    this.dueDate,
    this.minFiles = 0,
    this.reviewNote = '',
    this.customerNote = '',
    this.files = const [],
    this.requestedAt,
    this.completedAt,
  });

  final String id;
  final String number;
  final String title;
  final String description;
  final String category;
  final String projectId;
  final String projectName;

  /// Which milestone of their own application this unblocks.
  final String stepKey;
  final String stepName;

  final String status;
  final String priority;
  final bool mandatory;
  final DateTime? dueDate;
  final int minFiles;

  /// What the desk said back — on a Rejected request this is the whole point.
  final String reviewNote;
  final String customerNote;
  final List<RequestedFile> files;
  final DateTime? requestedAt;
  final DateTime? completedAt;

  /// Is the customer still expected to do something?
  ///
  /// SUBMITTED counts as DONE here, unlike on the office's side: they have sent
  /// it, and a list that keeps nagging after somebody has complied is a list
  /// they stop opening. Rejected comes back to them, because that one genuinely
  /// needs a second attempt.
  bool get needsAction => status == 'Pending' || status == 'Rejected';

  bool get isOverdue =>
      needsAction && dueDate != null && dueDate!.isBefore(DateTime.now());

  /// Sent, and now waiting on the office rather than on them.
  bool get awaitingReview => status == 'Submitted';

  LinearGradient get toneGradient => switch (status) {
        'Completed' => AppColors.leaf,
        'Submitted' => AppColors.sky,
        'Rejected' => AppColors.rose,
        _ => AppColors.brand,
      };

  static DocumentRequest fromJson(Map<String, dynamic> json) {
    String s(String k) => '${json[k] ?? ''}'.trim();
    // parseDate, not a local DateTime.tryParse: API Maker sends a date as an
    // ISO string, as a `{ $date: … }` wrapper or as epoch milliseconds
    // depending on the field, and tryParse answers null to the last two. A
    // due date that silently disappeared would take `isOverdue` with it — the
    // request would sit there looking optional.
    DateTime? d(String k) => parseDate(json[k]);

    return DocumentRequest(
      id: s('id'),
      number: s('number'),
      title: s('title').isEmpty ? 'Document' : s('title'),
      description: s('description'),
      category: s('category'),
      projectId: s('projectId'),
      projectName: s('projectName'),
      stepKey: s('stepKey'),
      stepName: s('stepName'),
      status: s('status').isEmpty ? 'Pending' : s('status'),
      priority: s('priority').isEmpty ? 'Normal' : s('priority'),
      mandatory: json['mandatory'] != false,
      dueDate: d('dueDate'),
      minFiles: int.tryParse('${json['minFiles'] ?? 0}') ?? 0,
      reviewNote: s('reviewNote'),
      customerNote: s('customerNote'),
      files: (json['files'] is List ? json['files'] as List : const [])
          .whereType<Map>()
          .map((raw) {
        final f = Map<String, dynamic>.from(raw);
        return RequestedFile(
          name: '${f['name'] ?? 'file'}',
          url: '${f['url'] ?? ''}',
          thumbUrl: '${f['thumbUrl'] ?? ''}',
          size: int.tryParse('${f['size'] ?? 0}') ?? 0,
          source: '${f['source'] ?? 'staff'}',
          uploadedAt: parseDate(f['uploadedAt']),
        );
      }).toList(),
      requestedAt: d('requestedAt'),
      completedAt: d('completedAt'),
    );
  }
}
