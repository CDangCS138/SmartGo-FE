import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/errors/failures.dart';
import 'package:smartgo/domain/repositories/payment_repository.dart';

@injectable
class CreateVnpayPaymentUseCase {
  final PaymentRepository repository;

  CreateVnpayPaymentUseCase(this.repository);

  Future<Either<Failure, PaymentUrlResult>> call({
    required int amount,
    required String orderDescription,
    required String orderType,
    String? bankCode,
    String? locale,
  }) async {
    return await repository.createVnpayPayment(
      amount: amount,
      orderDescription: orderDescription,
      orderType: orderType,
      bankCode: bankCode,
      locale: locale,
    );
  }
}
