class VnpayCreatePaymentResponse {
  final String paymentUrl;
  final String txnRef;

  const VnpayCreatePaymentResponse({
    required this.paymentUrl,
    required this.txnRef,
  });

  factory VnpayCreatePaymentResponse.fromJson(Map<String, dynamic> json) {
    // Handle both nested and flat response structures
    final data = json['data'] as Map<String, dynamic>? ?? json;

    return VnpayCreatePaymentResponse(
      paymentUrl: data['paymentUrl'] as String,
      txnRef: data['txnRef'] as String,
    );
  }
}

class VnpayReturnResponse {
  final bool success;
  final String responseCode;
  final String txnRef;
  final int amount;
  final String bankCode;
  final String transactionNo;
  final String orderInfo;
  final String payDate;
  final String? qrData;

  const VnpayReturnResponse({
    required this.success,
    required this.responseCode,
    required this.txnRef,
    required this.amount,
    required this.bankCode,
    required this.transactionNo,
    required this.orderInfo,
    required this.payDate,
    this.qrData,
  });

  static String? _readOptionalString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    }
    return null;
  }

  factory VnpayReturnResponse.fromJson(Map<String, dynamic> json) {
    // Handle both nested and flat response structures
    final data = json['data'] as Map<String, dynamic>? ?? json;

    final qrData = _readOptionalString(
      data,
      [
        'qrData',
        'qr_code',
        'qrCode',
        'ticketCode',
        'ticket_code',
        'qr',
      ],
    );

    return VnpayReturnResponse(
      success: data['success'] as bool? ?? false,
      responseCode: data['responseCode'] as String? ?? '',
      txnRef: data['txnRef'] as String? ?? '',
      amount: data['amount'] as int? ?? 0,
      bankCode: data['bankCode'] as String? ?? '',
      transactionNo: data['transactionNo'] as String? ?? '',
      orderInfo: data['orderInfo'] as String? ?? '',
      payDate: data['payDate'] as String? ?? '',
      qrData: qrData,
    );
  }
}

class VnpayIpnResponse {
  final String rspCode;
  final String message;

  const VnpayIpnResponse({
    required this.rspCode,
    required this.message,
  });

  factory VnpayIpnResponse.fromJson(Map<String, dynamic> json) {
    return VnpayIpnResponse(
      rspCode: json['RspCode'] as String? ?? '00',
      message: json['Message'] as String? ?? 'Confirm Success',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'RspCode': rspCode,
      'Message': message,
    };
  }
}

class MomoIpnResponse {
  final int resultCode;
  final String message;

  const MomoIpnResponse({
    required this.resultCode,
    required this.message,
  });

  factory MomoIpnResponse.fromJson(Map<String, dynamic> json) {
    return MomoIpnResponse(
      resultCode: json['resultCode'] as int? ?? -1,
      message: json['message'] as String? ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'resultCode': resultCode,
      'message': message,
    };
  }
}
