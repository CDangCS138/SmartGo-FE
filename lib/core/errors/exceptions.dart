class ServerException implements Exception {
  final String message;
  const ServerException([this.message = 'Server error occurred']);
}

class CacheException implements Exception {
  final String message;
  const CacheException([this.message = 'Cache error occurred']);
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Network error occurred']);
}

class ValidationException implements Exception {
  final String message;
  const ValidationException([this.message = 'Validation error occurred']);
}

class NotFoundException implements Exception {
  final String message;
  const NotFoundException([this.message = 'Resource not found']);
}

class BadRequestException implements Exception {
  final String message;
  const BadRequestException([this.message = 'Bad request']);
}

class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException([this.message = 'Unauthorized']);
}
