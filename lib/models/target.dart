class Target {
  final String databaseName;
  final String displayName;
  final String? smtpServer;
  final int? smtpPort;
  final String emailUser;
  final String emailPassword;
  final bool emailUseTls;
  final String toEmails;
  final String? ccEmails;
  final bool isActive;

  Target({
    required this.databaseName,
    required this.displayName,
    this.smtpServer,
    this.smtpPort,
    required this.emailUser,
    required this.emailPassword,
    this.emailUseTls = false,
    required this.toEmails,
    this.ccEmails,
    this.isActive = true,
  });

  factory Target.fromJson(Map<String, dynamic> json) => Target(
    databaseName: json['databaseName'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    smtpServer: json['smtpServer'] as String?,
    smtpPort: json['smtpPort'] as int?,
    emailUser: json['emailUser'] as String? ?? '',
    emailPassword: json['emailPassword'] as String? ?? '',
    emailUseTls: json['emailUseTls'] as bool? ?? false,
    toEmails: json['toEmails'] as String? ?? '',
    ccEmails: json['ccEmails'] as String?,
    isActive: json['isActive'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'databaseName': databaseName,
    'displayName': displayName,
    if (smtpServer != null && smtpServer!.isNotEmpty) 'smtpServer': smtpServer,
    if (smtpPort != null) 'smtpPort': smtpPort,
    'emailUser': emailUser,
    'emailPassword': emailPassword,
    'emailUseTls': emailUseTls,
    'toEmails': toEmails,
    if (ccEmails != null && ccEmails!.isNotEmpty) 'ccEmails': ccEmails,
    'isActive': isActive,
  };
}
