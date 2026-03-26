class VnpayCreatePaymentRequest {
  final int amount;
  final String orderDescription;
  final String orderType;
  final String? bankCode;
  final String? locale;

  const VnpayCreatePaymentRequest({
    required this.amount,
    required this.orderDescription,
    required this.orderType,
    this.bankCode,
    this.locale,
  });

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'orderDescription': orderDescription,
      'orderType': orderType,
      if (bankCode != null) 'bankCode': bankCode,
      if (locale != null) 'locale': locale,
    };
  }
}
