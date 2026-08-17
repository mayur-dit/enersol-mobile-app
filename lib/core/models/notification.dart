import '../utils/date_format.dart';

/// One row of `ens_notifications`, as this app reads it.
///
/// The collection is shared with the admin panel and the engineer PWA — the
/// backend fans an event out ONE ROW PER RECIPIENT on write, so a customer is
/// simply another recipient and nothing about the notification pipeline is
/// customer-shaped. What differs is only which link a shell follows: the web
/// panel uses `enot_link_str`, this app and the field app use
/// `enot_mobileLink_str`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.link,
    required this.entity,
    required this.entityId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    String s(String key) => '${json[key] ?? ''}'.trim();
    return AppNotification(
      id: s('_id'),
      type: s('enot_type_str'),
      title: s('enot_title_str'),
      body: s('enot_body_str'),
      // Falls back to the web link rather than to nothing: a row written by a
      // code path that only set one link should still be tappable, and landing
      // on the wrong screen beats a dead notification.
      link: s('enot_mobileLink_str').isNotEmpty
          ? s('enot_mobileLink_str')
          : s('enot_link_str'),
      entity: s('enot_entity_str'),
      entityId: s('enot_entityId_str'),
      isRead: json['enot_isRead_bl'] == true,
      createdAt: parseDate(s('createdAt')),
    );
  }

  final String id;
  final String type;
  final String title;
  final String body;
  final String link;
  final String entity;
  final String entityId;
  final bool isRead;
  final DateTime? createdAt;

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        link: link,
        entity: entity,
        entityId: entityId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );

  /// "just now" / "12m" / "3h" / "5d" — a notification list needs no more.
  String get age {
    final at = createdAt;
    if (at == null) return '';
    final secs = DateTime.now().difference(at).inSeconds;
    if (secs < 45) return 'just now';
    final mins = (secs / 60).round();
    if (mins < 60) return '${mins}m';
    final hrs = (mins / 60).round();
    if (hrs < 24) return '${hrs}h';
    final days = (hrs / 24).round();
    if (days < 7) return '${days}d';
    return fmtDate(at, fallback: '');
  }
}
