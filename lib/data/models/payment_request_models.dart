class VnpayCreatePaymentRequest {
  final int amount;
  final String orderDescription;
  final String orderType;
  final String? billId;
  final String? bankCode;
  final String? locale;
  final String? platform;
  final String? returnUrl;

  const VnpayCreatePaymentRequest({
    required this.amount,
    required this.orderDescription,
    required this.orderType,
    this.billId,
    this.bankCode,
    this.locale,
    this.platform,
    this.returnUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'orderDescription': orderDescription,
      'orderType': orderType,
      if (billId != null) 'billId': billId,
      if (bankCode != null) 'bankCode': bankCode,
      if (locale != null) 'locale': locale,
      if (platform != null) 'platform': platform,
      if (returnUrl != null) 'returnUrl': returnUrl,
    };
  }
}
