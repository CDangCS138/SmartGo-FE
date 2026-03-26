import 'package:dartz/dartz.dart';
import 'package:smartgo/core/errors/failures.dart';

abstract class PaymentRepository {
  Future<Either<Failure, PaymentUrlResult>> createVnpayPayment({
    required int amount,
    required String orderDescription,
    required String orderType,
    String? bankCode,
    String? locale,
  });

  Future<Either<Failure, PaymentResultData>> getVnpayReturnResult();

  Future<Either<Failure, IpnAcknowledgement>> handleVnpayIpn();
}

class PaymentUrlResult {
  final String paymentUrl;
  final String txnRef;

  const PaymentUrlResult({
    required this.paymentUrl,
    required this.txnRef,
  });
}

class PaymentResultData {
  final bool success;
  final String responseCode;
  final String txnRef;
  final int amount;
  final String bankCode;
  final String transactionNo;
  final String orderInfo;
  final String payDate;

  const PaymentResultData({
    required this.success,
    required this.responseCode,
    required this.txnRef,
    required this.amount,
    required this.bankCode,
    required this.transactionNo,
    required this.orderInfo,
    required this.payDate,
  });
}

class IpnAcknowledgement {
  final String rspCode;
  final String message;

  const IpnAcknowledgement({
    required this.rspCode,
    required this.message,
  });
}
