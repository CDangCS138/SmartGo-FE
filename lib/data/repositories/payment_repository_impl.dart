import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:smartgo/core/errors/exceptions.dart';
import 'package:smartgo/core/errors/failures.dart';
import 'package:smartgo/data/datasources/payment_remote_data_source.dart';
import 'package:smartgo/data/models/payment_request_models.dart';
import 'package:smartgo/domain/repositories/payment_repository.dart';

@LazySingleton(as: PaymentRepository)
class PaymentRepositoryImpl implements PaymentRepository {
  final PaymentRemoteDataSource remoteDataSource;

  PaymentRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, PaymentUrlResult>> createVnpayPayment({
    required int amount,
    required String orderDescription,
    required String orderType,
    String? bankCode,
    String? locale,
  }) async {
    try {
      final request = VnpayCreatePaymentRequest(
        amount: amount,
        orderDescription: orderDescription,
        orderType: orderType,
        bankCode: bankCode,
        locale: locale,
      );

      final response = await remoteDataSource.createVnpayPayment(request, null);

      return Right(
        PaymentUrlResult(
          paymentUrl: response.paymentUrl,
          txnRef: response.txnRef,
        ),
      );
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on BadRequestException catch (e) {
      return Left(BadRequestFailure(e.message));
    } on UnauthorizedException catch (e) {
      return Left(UnauthorizedFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, PaymentResultData>> getVnpayReturnResult() async {
    try {
      final response = await remoteDataSource.getVnpayReturnResult(null);

      return Right(
        PaymentResultData(
          success: response.success,
          responseCode: response.responseCode,
          txnRef: response.txnRef,
          amount: response.amount,
          bankCode: response.bankCode,
          transactionNo: response.transactionNo,
          orderInfo: response.orderInfo,
          payDate: response.payDate,
        ),
      );
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NotFoundException catch (e) {
      return Left(NotFoundFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }

  @override
  Future<Either<Failure, IpnAcknowledgement>> handleVnpayIpn() async {
    try {
      final response = await remoteDataSource.handleVnpayIpn(null);

      return Right(
        IpnAcknowledgement(
          rspCode: response.rspCode,
          message: response.message,
        ),
      );
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(UnexpectedFailure('An unexpected error occurred: $e'));
    }
  }
}
