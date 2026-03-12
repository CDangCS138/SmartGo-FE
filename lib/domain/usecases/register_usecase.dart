import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../core/errors/failures.dart';
import '../entities/auth_tokens.dart';
import '../repositories/auth_repository.dart';

@injectable
class RegisterUseCase {
  final AuthRepository repository;

  RegisterUseCase(this.repository);

  Future<Either<Failure, AuthTokens>> call({
    required String email,
    required String name,
    required String password,
  }) async {
    return await repository.register(
      email: email,
      name: name,
      password: password,
    );
  }
}
