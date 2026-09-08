import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../config/env.dart';
import '../models/customer_models.dart';
import '../models/picked_upload.dart';
import '../state/auth_service.dart';
import '../utils/date_format.dart';

/// Reads everything the customer screens display, scoped to the signed-in user.
///
/// Every read goes through the "Enersol Customer Portal" custom API, which
/// derives the caller's identity from their token and filters to that user
/// server-side — the app never queries a business collection directly, so one
/// customer can never see another's data. This class only shapes the raw rows
/// the portal returns into the screens' view models.
class CustomerRepository {
  CustomerRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthService _auth;

  /// Bumped whenever something the office did may have changed what these
  /// screens should be showing.
  ///
  /// WHY A SIGNAL AND NOT A CACHE. Every screen loads its data once, in
  /// `initState`, and the shell keeps all five alive in an IndexedStack — so a
  /// screen built at sign-in went on showing that first answer until the app was
  /// killed and reopened. A customer who was told "a new document is available"
  /// opened the Documents tab and read "No documents yet", and one whose lead
  /// was confirmed while the app sat open kept reading "No applications yet".
  /// Both were true when the screen loaded and stale by the time it was read.
  ///
  /// [ScreenRefresh] listens to this and re-reads — immediately for the tab on
  /// screen, on arrival for the ones behind it.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Say that everything held on screen may now be out of date.
  ///
  /// Called when a notification arrives (the office just did something to this
  /// customer's job) and when the app comes back to the foreground — the two
  /// moments where the phone knows the world moved on without it.
  void invalidate() {
    // The coalescing window below must not answer a deliberate re-read with the
    // request that was already in flight when the news arrived.
    _appsInFlight = null;
    _appsInFlightAt = null;
    revision.value++;
  }

  /// The project ids seen on the last applications() load.
  ///
  /// Read by [hasCommissionedProject], which is what lets the Service screen say
  /// plainly that a request will be logged against the enquiry rather than
  /// against a system — the app used to find that out by being refused.
  List<String>? _projectCache;

  /// True once at least one of this customer's jobs has been confirmed. Null
  /// until [applications] has run at least once.
  bool? get hasCommissionedProject => _projectCache?.isNotEmpty;

  /// How close together two [applications] calls have to land to be treated
  /// as the same request. Wide enough to catch a cold start's near-tied
  /// widget mounts, narrow enough that nobody mistakes it for caching.
  static const _coalesceWindow = Duration(seconds: 2);

  // ── Application ──────────────────────────────────────────────────────────

  /// A request already on its way, and when it started — see [applications].
  Future<List<SolarApplication>>? _appsInFlight;
  DateTime? _appsInFlightAt;

  /// Confirmed projects first, then any application still sitting as a lead.
  ///
  /// One portal call returns each job with its timeline already composed — see
  /// [_fetchApplications] for why the shaping is not done here.
  ///
  /// COALESCES near-simultaneous callers onto one request. Home and the
  /// Application tab both load this independently, and both mount within a
  /// couple of frames of each other on a cold start — without this they fired
  /// two identical portal round trips before either had a chance to finish. A
  /// short window rather than an unbounded cache: a DELIBERATE pull-to-refresh
  /// seconds or minutes later must still hit the network, not a startup echo.
  Future<List<SolarApplication>> applications() {
    final inFlight = _appsInFlight;
    final startedAt = _appsInFlightAt;
    if (inFlight != null &&
        startedAt != null &&
        DateTime.now().difference(startedAt) < _coalesceWindow) {
      return inFlight;
    }

    _appsInFlightAt = DateTime.now();
    final future = _fetchApplications();
    _appsInFlight = future;
    // Cleared once it settles (success or failure) rather than after the
    // window expires — a slow request must not go on serving a stale future to
    // callers that already moved past the coalescing window.
    // `.ignore()` because whenComplete hands back a SECOND future carrying the
    // same failure, and nothing listens to it — Dart reports that as an
    // unhandled async error even though the real caller below handles it
    // perfectly well. The bookkeeping runs either way.
    future.whenComplete(() {
      if (identical(_appsInFlight, future)) _appsInFlight = null;
    }).ignore();
    return future;
  }

  /// Maps the portal's `applications` payload.
  ///
  /// The shaping — which milestones exist, their order, and which one the job is
  /// sitting on — happens SERVER-SIDE now. Those milestones are the office's own
  /// pipeline columns, which are editable masters, so a client that composes its
  /// own list goes stale the moment somebody edits one. That is exactly what had
  /// happened: this file used to walk a fixed `['Open','New','Qualified',…]`
  /// status ladder that the admin panel stopped writing when stage became the
  /// only axis on Leads.
  Future<List<SolarApplication>> _fetchApplications() async {
    final data = await _api.portal('applications');
    final rows = ApiClient.asRows(data['applications']);

    // A job counts as commissioned when the server says it is CONFIRMED, with
    // the project id as the identifier. Keying off the id alone was wrong in
    // one direction that matters: a confirmed job whose row carries no project
    // id — a lead converted before project ids existed, or one whose project
    // was opened without the code being mirrored back — read as "no system on
    // your account", which is precisely the state the Service screen uses this
    // to explain. The reference is the fallback so the entry is never empty.
    _projectCache = rows
        .where((a) => a['isConfirmed'] == true || '${a['projectId'] ?? ''}'.isNotEmpty)
        .map((a) {
          final id = '${a['projectId'] ?? ''}'.trim();
          return id.isNotEmpty ? id : '${a['reference'] ?? ''}'.trim();
        })
        .where((n) => n.isNotEmpty)
        .toList();

    return rows.map(_applicationFrom).toList();
  }

  SolarApplication _applicationFrom(Map<String, dynamic> a) {
    final stages = ApiClient.asRows(a['stages'])
        .map((s) => AppStage(
              label: '${s['label'] ?? ''}',
              state: AppStage.stateFrom('${s['state'] ?? ''}'),
              date: _date(s['date']),
              note: _clean(s['note']),
              group: '${s['group'] ?? ''}',
              key: '${s['key'] ?? ''}',
            ))
        .where((s) => s.label.isNotEmpty)
        .toList();

    return SolarApplication(
      reference: '${a['reference'] ?? ''}',
      status: '${a['status'] ?? ''}',
      stage: '${a['stage'] ?? ''}',
      leadId: _clean(a['leadId']),
      projectId: _clean(a['projectId']),
      projectName: _clean(a['projectName']),
      capacityKw: (_num(a['capacityKw']) ?? 0).toDouble(),
      submittedOn: _date(a['submittedOn']) ?? DateTime.now(),
      siteAddress: _clean(a['siteAddress']),
      discom: _clean(a['discom']),
      projectType: _clean(a['projectType']),
      isConfirmed: a['isConfirmed'] == true,
      stages: stages,
    );
  }

  /// The electricity boards a customer can pick from — a required field on a
  /// lead, so the form cannot submit without one.
  Future<List<String>> discoms() async {
    final data = await _api.portal('discoms');
    final list = data['discoms'];
    if (list is List) {
      return list
          .map((d) => '$d'.trim())
          .where((n) => n.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// Files a new lead, tagged to this customer so it appears in their list.
  ///
  /// Goes through the PORTAL, not `/create-lead`.
  ///
  /// Calling create-lead directly needed a second transport grant on the
  /// customer api-user — the exact surface the portal exists to keep to one
  /// door — and, worse, that endpoint takes the whole `elead_*` body verbatim,
  /// so a lifted customer token could have set the owner, the stage, the dealer
  /// code, anything. The portal action takes only the handful of fields a
  /// homeowner can actually know and writes the rest server-side, minting the id
  /// from the same atomic counter as a lead keyed in by sales.
  Future<String> submitApplication({
    required String name,
    required String mobile,
    required String address,
    required String city,
    required String pincode,
    required double capacityKw,
    required String discom,
    String? notes,
    String? referralCode,
  }) async {
    // Upper-cased and trimmed HERE, not on the form: the code is quoted from a
    // WhatsApp forward or read off a friend's screen, so it arrives with stray
    // spaces and in whatever case the keyboard was in, and the server matches
    // `erf_code_str` exactly. An empty box must send no key at all — the portal
    // treats a present-but-blank code as a code it could not find and logs a
    // warning about a referral nobody claimed.
    final code = (referralCode ?? '').trim().toUpperCase();

    final data = await _api.portal('submitApplication', params: {
      'name': name,
      'mobile': mobile,
      'address': address,
      'city': city,
      'pincode': pincode,
      // A homeowner rarely knows their kW, so a blank form field files as 0 and
      // sales sets the real figure after the survey.
      'capacityKw': capacityKw,
      'discom': discom,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (code.isNotEmpty) 'referralCode': code,
    });

    _projectCache = null;
    // The list must not serve a cached "no applications" straight after the
    // customer filed one — this is the one moment they will definitely look.
    _appsInFlight = null;
    _appsInFlightAt = null;

    final ref = '${data['leadId'] ?? ''}'.trim();
    return ref.isEmpty ? 'Submitted' : ref;
  }

  // ── Documents ────────────────────────────────────────────────────────────

  Future<List<CustomerDocument>> warrantyDocuments() => _documentsOfGroup('warranty');
  Future<List<CustomerDocument>> otherDocuments() => _documentsOfGroup('other');

  /// A stored file reference the OS can actually open.
  ///
  /// The admin panel stores what its upload API hands back, and that is a path
  /// RELATIVE to the API host (`/api/custom-api/enersol/serve-file?…`). That is
  /// a perfectly good src for a browser sitting on the same origin, and nothing
  /// at all to a phone: `launchUrl` cannot resolve a bare path, so tapping the
  /// document did nothing and the customer concluded the file was broken.
  /// Anything already absolute — a DISCOM portal link someone pasted — is left
  /// exactly as it is.
  String? _fileUrl(Object? raw) {
    final url = _clean(raw);
    if (url == null) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${Env.apiHost}${url.startsWith('/') ? '' : '/'}$url';
  }

  Future<List<CustomerDocument>> _documentsOfGroup(String group) async {
    final data = await _api.portal('documents', params: {'group': group});
    final rows = ApiClient.asRows(data['documents']);

    return rows
        .map((d) => CustomerDocument(
              title: '${d['ecd_title_str'] ?? 'Document'}',
              category: '${d['ecd_category_str'] ?? 'Documents'}',
              issuedOn: _date(d['ecd_issuedOn_date']) ??
                  _date(d['createdAt']) ??
                  DateTime.now(),
              url: _fileUrl(d['ecd_fileUrl_str']),
              fileName: _clean(d['ecd_fileName_str']),
              sizeLabel: _size(_num(d['ecd_size_num'])),
              validUntil: _date(d['ecd_validUntil_date']),
            ))
        .toList();
  }

  // ── Service (O&M) ────────────────────────────────────────────────────────

  Future<List<ServiceRequest>> serviceRequests() async {
    final data = await _api.portal('serviceRequests');
    final rows = ApiClient.asRows(data['requests']);

    return rows.map((r) {
      final logs = ((r['esr_logs_arr'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          // Staff can mark a note internal; those must not surface here.
          .where((l) => l['log_isVisibleToCustomer_bl'] != false)
          .map((l) => ServiceLog(
                at: _date(l['log_at_date']) ?? DateTime.now(),
                by: '${l['log_by_str'] ?? 'Enersol'}',
                note: '${l['log_note_str'] ?? ''}',
              ))
          .toList()
        ..sort((a, b) => a.at.compareTo(b.at));

      final status = '${r['esr_status_str'] ?? 'Open'}';
      final resolved = _date(r['esr_resolvedAt_date']);

      return ServiceRequest(
        reference: '${r['esr_requestNumber_str'] ?? ''}',
        type: '${r['esr_type_str'] ?? 'Other'}',
        description: '${r['esr_description_str'] ?? ''}',
        status: status,
        raisedOn: _date(r['createdAt']) ?? DateTime.now(),
        logs: logs,
        closedOn: (status == 'Resolved' || status == 'Cancelled')
            ? (resolved ?? _date(r['updatedAt']))
            : null,
      );
    }).toList();
  }

  Future<String> raiseServiceRequest({
    required String type,
    required String description,
  }) async {
    // The portal mints the number and stamps the customer from the token, so a
    // request can only ever be filed against the caller's own account. It picks
    // the project itself; a customer with more than one is rare enough that a
    // picker here would be a question almost nobody needs asked.
    final data = await _api.portal('raiseService', params: {
      'type': type,
      'description': description,
    });
    final ref = '${data['requestNumber'] ?? ''}';
    return ref.isEmpty ? 'Submitted' : ref;
  }

  // ── Referral ─────────────────────────────────────────────────────────────

  Future<ReferralSummary> referrals() async {
    // The share code lives on the user, so the screen is useful even before the
    // first referral — always return a summary rather than letting a failure
    // collapse to an "unavailable" state.
    final fallbackCode = _auth.user?.referralCode?.trim() ?? '';

    Map<String, dynamic> data;
    try {
      data = await _api.portal('referrals');
    } catch (_) {
      // pointsOnInstall stays 0: a screen that could not reach the server must
      // not quote a reward it cannot stand behind.
      return ReferralSummary(
        code: fallbackCode.isNotEmpty ? fallbackCode : '—',
        totalPoints: 0,
        referrals: const [],
      );
    }

    final rows = ApiClient.asRows(data['referrals']);
    final list = rows
        .map((r) => Referral(
              name: '${r['erf_name_str'] ?? ''}',
              status: '${r['erf_status_str'] ?? 'Enquiry'}',
              referredOn: _date(r['erf_referredOn_date']) ??
                  _date(r['createdAt']) ??
                  DateTime.now(),
              pointsEarned: (_num(r['erf_pointsEarned_num']) ?? 0).round(),
            ))
        .toList();

    final total = list.fold<int>(0, (sum, r) => sum + r.pointsEarned);
    final code = '${data['code'] ?? ''}'.trim().isNotEmpty
        ? '${data['code']}'.trim()
        : fallbackCode;

    return ReferralSummary(
      code: code.isEmpty ? '—' : code,
      totalPoints: total,
      referrals: list,
      // The office's figure, shipped with the rows. An older backend that does
      // not send it leaves this 0, and the screen simply says nothing about
      // what a pending referral is worth.
      pointsOnInstall: (_num(data['pointsOnInstall']) ?? 0).round(),
    );
  }

  // ── Generation ───────────────────────────────────────────────────────────

  /// Generation now reads what the office actually entered.
  ///
  /// This used to serve a fixed "representative week" — 9,420 kWh lifetime for
  /// every customer in the country — behind a small notice saying so. Real
  /// readings exist (the admin panel's Generation master writes them by hand
  /// while the inverter-portal sync waits on the vendor's API), and a customer
  /// comparing an invented figure against their own meter has been told
  /// something untrue about their own roof. An honest empty screen is the
  /// cheaper of the two.
  Future<GenerationSummary?> generation() => _liveGeneration();

  Future<GenerationSummary?> _liveGeneration() async {
    final data = await _api.portal('generation');
    final rows = ApiClient.asRows(data['readings']);
    if (rows.isEmpty) return null;

    final byDay = rows
        .map((r) => (
              day: _date(r['egr_date']) ?? DateTime.now(),
              kwh: (_num(r['egr_kwh_num']) ?? 0).toDouble(),
              lifetime: (_num(r['egr_lifetimeKwh_num']) ?? 0).toDouble(),
              currentKw: (_num(r['egr_currentKw_num']) ?? 0).toDouble(),
              syncedAt: _date(r['egr_syncedAt_date']),
            ))
        .toList();

    final today = DateTime.now();
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final todayRow = byDay.where((r) => sameDay(r.day, today)).firstOrNull;
    final monthKwh = byDay
        .where((r) => r.day.year == today.year && r.day.month == today.month)
        .fold<double>(0, (sum, r) => sum + r.kwh);

    // Newest first from the query; the last 7 days read oldest-first for the chart.
    final last7 = byDay.take(7).toList().reversed
        .map((r) => GenerationPoint(day: r.day, kwh: r.kwh))
        .toList();

    // Installed capacity comes back with the readings, for the "% of capacity".
    final capacity = (_num(data['capacityKw']) ?? 0).toDouble();

    return GenerationSummary(
      todayKwh: todayRow?.kwh ?? 0,
      monthKwh: monthKwh,
      lifetimeKwh: byDay.first.lifetime,
      currentKw: todayRow?.currentKw ?? 0,
      capacityKw: capacity,
      last7Days: last7,
      lastSyncedAt: byDay.first.syncedAt ?? byDay.first.day,
    );
  }

  // ── Document requests ────────────────────────────────────────────────────

  /// What the office is waiting on FROM this customer.
  ///
  /// Sorted so the ones needing action come first: this list is a to-do list,
  /// not an archive, and a screen that opens on six completed rows is a screen
  /// that gets closed again.
  Future<List<DocumentRequest>> documentRequests({String? projectId}) async {
    final data = await _api.portal(
      'documentRequests',
      params: projectId == null || projectId.isEmpty
          ? null
          : {'projectId': projectId},
    );
    final list = ApiClient.asRows(data['requests'])
        .map(DocumentRequest.fromJson)
        .where((r) => r.id.isNotEmpty)
        .toList();

    list.sort((a, b) {
      // Needs-action first, then awaiting review, then done.
      int rank(DocumentRequest r) =>
          r.needsAction ? 0 : (r.awaitingReview ? 1 : 2);
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      // Within a group, the one due soonest. No due date sorts last — it is
      // the least urgent thing in a list of urgent things.
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return list;
  }

  /// Send files against one request.
  ///
  /// TWO STEPS, deliberately: every file goes to OneDrive through the shared
  /// uploader first, and only the resulting URLs are posted to the portal. A
  /// single multipart call into the portal would have meant a second uploader
  /// with its own size rules and its own storage accounting, and a half-finished
  /// transfer would leave a request pointing at bytes that are not there.
  ///
  /// A file that fails to upload aborts the whole submission rather than sending
  /// a partial set: "I sent you three pages" and "we received two" is the
  /// argument this screen exists to prevent.
  Future<void> submitDocumentRequest({
    required String requestId,
    required List<PickedUpload> files,
    String note = '',
  }) async {
    final uploaded = <Map<String, dynamic>>[];
    for (final file in files) {
      final res = await _api.uploadFile(file, folder: 'document-requests');
      final url = '${res['uploadPath'] ?? ''}';
      if (url.isEmpty) {
        throw ApiException('That file could not be uploaded. Please try again.');
      }
      uploaded.add({
        'fileId': '${res['fileId'] ?? ''}',
        'name': '${res['originalName'] ?? file.name}',
        'url': url,
        'thumbUrl': '${res['thumbnailPath'] ?? ''}',
        'size': res['fileSize'] ?? 0,
      });
    }

    await _api.portal('submitDocumentRequest', params: {
      'requestId': requestId,
      'files': uploaded,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    // The office's view of this job just changed, and so did every screen that
    // counts outstanding requests.
    invalidate();
  }

  // ── Parsing helpers ──────────────────────────────────────────────────────

  /// Mongo dates arrive as ISO strings, sometimes as `{$date: …}`.
  ///
  /// Delegates to [parseDate], which lands them in LOCAL time. That matters:
  /// the API sends UTC, and a UTC `DateTime` formats and compares on its UTC
  /// calendar day — so an IST date used to render (and be bucketed by
  /// [_liveGeneration]) as the day before.
  static DateTime? _date(dynamic v) => parseDate(v);

  static num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse('$v');
  }

  static String? _clean(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  static String? _size(num? bytes) {
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
