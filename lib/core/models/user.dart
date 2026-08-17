/// A row of `ens_users`, minus the password the API never returns.
///
/// Mirrors `enersol-admin-fe/src/app/core/models/user.model.ts`.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.userName,
    required this.userType,
    required this.role,
    this.email,
    this.mobile,
    this.companyName,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.gstin,
    this.referralCode,
  });

  final String id;
  final String name;
  final String userName;

  /// SYSTEM_USER | CUSTOMER | VENDOR.
  final String userType;

  /// Role CODE, joins to `ens_user_roles.erol_code_str`.
  final String role;

  final String? email;
  final String? mobile;
  final String? companyName;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? gstin;

  /// Shareable referral code, issued with the login by staff.
  final String? referralCode;

  bool get isCustomer => userType == 'CUSTOMER';

  /// Initials for the avatar, e.g. "Ravi Mehta" -> "RM".
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    // ens_mobile_num is a number in the schema but arrives as num or String
    // depending on how it was written; normalise to a display string.
    final mobileRaw = json['ens_mobile_num'];
    return AppUser(
      id: '${json['_id'] ?? ''}',
      name: '${json['ens_name_str'] ?? ''}',
      userName: '${json['ens_userName_str'] ?? ''}',
      userType: '${json['ens_userType_str'] ?? ''}',
      role: '${json['ens_role_str'] ?? ''}',
      email: json['ens_email_str']?.toString(),
      mobile: mobileRaw == null ? null : '$mobileRaw',
      companyName: json['ens_companyName_str']?.toString(),
      address: json['ens_address_str']?.toString(),
      city: json['ens_city_str']?.toString(),
      state: json['ens_state_str']?.toString(),
      pincode: json['ens_pincode_str']?.toString(),
      gstin: json['ens_gstin_str']?.toString(),
      referralCode: json['ens_referralCode_str']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'ens_name_str': name,
        'ens_userName_str': userName,
        'ens_userType_str': userType,
        'ens_role_str': role,
        'ens_email_str': email,
        'ens_mobile_num': mobile,
        'ens_companyName_str': companyName,
        'ens_address_str': address,
        'ens_city_str': city,
        'ens_state_str': state,
        'ens_pincode_str': pincode,
        'ens_gstin_str': gstin,
        'ens_referralCode_str': referralCode,
      };
}

/// The persisted session: the user plus API Maker's two parallel tokens.
///
/// These are NOT access+refresh. They are two separate tokens sent on different
/// headers — `amToken` says what the api-user may call, `accessToken` says who
/// the signed-in user is.
class Session {
  const Session({
    required this.user,
    required this.amToken,
    required this.amRefreshToken,
    required this.accessToken,
    required this.refreshToken,
  });

  final AppUser user;
  final String amToken;
  final String amRefreshToken;
  final String accessToken;
  final String refreshToken;

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'amToken': amToken,
        'amRefreshToken': amRefreshToken,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        user: AppUser.fromJson(
          Map<String, dynamic>.from(json['user'] as Map),
        ),
        amToken: '${json['amToken'] ?? ''}',
        amRefreshToken: '${json['amRefreshToken'] ?? ''}',
        accessToken: '${json['accessToken'] ?? ''}',
        refreshToken: '${json['refreshToken'] ?? ''}',
      );
}
