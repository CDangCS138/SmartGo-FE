import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/errors/failures.dart';
import 'package:smartgo/domain/repositories/payment_repository.dart';

@injectable
class HandleVnpayIpnUseCase {
  final PaymentRepository repository;

  HandleVnpayIpnUseCase(this.repository);

  Future<Either<Failure, IpnAcknowledgement>> call() async {
    return await repository.handleVnpayIpn();
  }
}
