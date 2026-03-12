import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/enums/theme_mode.dart';
import '../../../core/services/storage_service.dart';
part 'theme_event.dart';
part 'theme_state.dart';

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  final StorageService _storageService;
  ThemeBloc(this._storageService) : super(const ThemeState()) {
    on<ThemeLoaded>(_onThemeLoaded);
    on<ThemeChanged>(_onThemeChanged);
  }
  Future<void> _onThemeLoaded(
    ThemeLoaded event,
    Emitter<ThemeState> emit,
  ) async {
    final savedTheme = _storageService.getThemeMode();
    if (savedTheme != null) {
      final themeMode = ThemeModeExtension.fromString(savedTheme);
      emit(state.copyWith(themeMode: themeMode));
    }
  }

  Future<void> _onThemeChanged(
    ThemeChanged event,
    Emitter<ThemeState> emit,
  ) async {
    await _storageService.saveThemeMode(event.themeMode.name);
    emit(state.copyWith(themeMode: event.themeMode));
  }
}
