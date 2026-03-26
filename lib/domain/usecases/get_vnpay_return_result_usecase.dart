import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/errors/failures.dart';
import 'package:smartgo/domain/repositories/payment_repository.dart';

@injectable
class GetVnpayReturnResultUseCase {
  final PaymentRepository repository;

  GetVnpayReturnResultUseCase(this.repository);

  Future<Either<Failure, PaymentResultData>> call() async {
    return await repository.getVnpayReturnResult();
  }
}
