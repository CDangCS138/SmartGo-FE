// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartgo/core/services/storage_service.dart';
import 'package:smartgo/main.dart';

void main() {
  testWidgets('SmartGo app loads', (WidgetTester tester) async {
    // Initialize mock shared preferences
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storageService = StorageService(prefs);

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(storageService: storageService));

    // Verify that login screen loads (since no auth token)
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
  });
}
