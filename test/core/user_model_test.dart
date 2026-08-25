import 'dart:convert';

import 'package:enersol_customer/core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

/// The signed-in user and the session that carries them.
///
/// Everything on this screen-facing model arrives as untyped JSON from a schema
/// that stores the mobile number as a NUMBER and everything else as a string.
/// A field read with the wrong assumption does not throw — it renders as
/// "null" on the profile screen, or as an empty avatar, and the customer sees
/// it before anybody else does.
///
/// [Session] is the other half: it is written to secure storage on sign-in and
/// read back on every launch, so a round trip that loses a token is a customer
/// who is silently signed out the next morning.

Map<String, dynamic> userJson({
  Object? id = '68f0000000000000000000aa',
  Object? name = 'Ravi Mehta',
  Object? mobile = 9876543210,
  Object? userType = 'CUSTOMER',
}) =>
    {
      '_id': id,
      'ens_name_str': name,
      'ens_userName_str': 'ravi',
      'ens_userType_str': userType,
      'ens_role_str': 'CUSTOMER',
      'ens_email_str': 'ravi@example.com',
      'ens_mobile_num': mobile,
      'ens_companyName_str': 'Mehta Textiles',
      'ens_address_str': 'Alkapuri',
      'ens_city_str': 'Vadodara',
      'ens_state_str': 'Gujarat',
      'ens_pincode_str': '390007',
      'ens_gstin_str': '24AAACM1234C1Z5',
      'ens_referralCode_str': 'RAVI100',
    };

void main() {
  group('AppUser.fromJson', () {
    test('reads every field the profile screen shows', () {
      final user = AppUser.fromJson(userJson());
      expect(user.id, '68f0000000000000000000aa');
      expect(user.name, 'Ravi Mehta');
      expect(user.userName, 'ravi');
      expect(user.userType, 'CUSTOMER');
      expect(user.role, 'CUSTOMER');
      expect(user.email, 'ravi@example.com');
      expect(user.companyName, 'Mehta Textiles');
      expect(user.city, 'Vadodara');
      expect(user.gstin, '24AAACM1234C1Z5');
      expect(user.referralCode, 'RAVI100');
    });

    test('normalises a numeric mobile to the string the UI prints', () {
      // ens_mobile_num is a number in the schema but arrives as either,
      // depending on how the row was written.
      expect(AppUser.fromJson(userJson(mobile: 9876543210)).mobile, '9876543210');
      expect(AppUser.fromJson(userJson(mobile: '9876543210')).mobile, '9876543210');
    });

    test('leaves a missing mobile null rather than printing "null"', () {
      expect(AppUser.fromJson(userJson(mobile: null)).mobile, isNull);
    });

    test('renders a missing required field as an empty string, never "null"', () {
      final user = AppUser.fromJson(const {});
      expect(user.id, '');
      expect(user.name, '');
      expect(user.userName, '');
      expect(user.userType, '');
      expect(user.role, '');
    });

    test('leaves every optional field null when the row omits it', () {
      final user = AppUser.fromJson(const {'_id': 'x'});
      expect(user.email, isNull);
      expect(user.companyName, isNull);
      expect(user.gstin, isNull);
      expect(user.referralCode, isNull);
    });

    test('stringifies an id the server sent as something other than a string', () {
      expect(AppUser.fromJson(userJson(id: 12345)).id, '12345');
    });
  });

  group('isCustomer', () {
    test('is true only for the one user type this app has screens for', () {
      expect(AppUser.fromJson(userJson()).isCustomer, isTrue);
      expect(AppUser.fromJson(userJson(userType: 'SYSTEM_USER')).isCustomer, isFalse);
      expect(AppUser.fromJson(userJson(userType: 'VENDOR')).isCustomer, isFalse);
      expect(AppUser.fromJson(userJson(userType: '')).isCustomer, isFalse);
    });

    test('is case-sensitive, because the schema enum is', () {
      expect(AppUser.fromJson(userJson(userType: 'customer')).isCustomer, isFalse);
    });
  });

  group('initials', () {
    test('takes the first and last name', () {
      expect(AppUser.fromJson(userJson(name: 'Ravi Mehta')).initials, 'RM');
    });

    test('skips the middle name rather than running three letters together', () {
      expect(AppUser.fromJson(userJson(name: 'Ravi Kumar Mehta')).initials, 'RM');
    });

    test('uses one letter for a single name', () {
      expect(AppUser.fromJson(userJson(name: 'Ravi')).initials, 'R');
    });

    test('upper-cases whatever it was given', () {
      expect(AppUser.fromJson(userJson(name: 'ravi mehta')).initials, 'RM');
    });

    test('copes with the padding and double spaces people type', () {
      expect(AppUser.fromJson(userJson(name: '  Ravi   Mehta  ')).initials, 'RM');
    });

    test('shows a placeholder rather than crashing the avatar on an empty name', () {
      expect(AppUser.fromJson(userJson(name: '')).initials, '?');
      expect(AppUser.fromJson(userJson(name: '   ')).initials, '?');
    });
  });

  group('Session', () {
    Session session() => Session(
          user: AppUser.fromJson(userJson()),
          amToken: 'am-token',
          amRefreshToken: 'am-refresh',
          accessToken: 'user-token',
          refreshToken: 'user-refresh',
        );

    test('survives the round trip through secure storage', () {
      // This is what a returning customer depends on: the blob written on
      // sign-in is decoded on the next launch, and anything lost here is a
      // silent sign-out the following morning.
      final restored = Session.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(session().toJson())) as Map),
      );
      expect(restored.amToken, 'am-token');
      expect(restored.amRefreshToken, 'am-refresh');
      expect(restored.accessToken, 'user-token');
      expect(restored.refreshToken, 'user-refresh');
      expect(restored.user.userName, 'ravi');
      expect(restored.user.mobile, '9876543210');
    });

    test('keeps the two token pairs apart — they are not access + refresh', () {
      final s = session();
      expect(s.amToken, isNot(s.accessToken));
      final json = s.toJson();
      expect(json['amToken'], 'am-token');
      expect(json['accessToken'], 'user-token');
    });

    test('reads a session written with a token missing as an empty string', () {
      final restored = Session.fromJson({
        'user': userJson(),
        'amToken': 'am-token',
      });
      expect(restored.accessToken, '');
      expect(restored.refreshToken, '');
      expect(restored.amRefreshToken, '');
    });

    test('carries the referral code, which the Referral screen has nowhere else to read', () {
      final restored = Session.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(session().toJson())) as Map),
      );
      expect(restored.user.referralCode, 'RAVI100');
    });
  });
}
