import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssh_client/data/host_repository.dart';
import 'package:ssh_client/main.dart';

void main() {
  testWidgets('host list shows before saved hosts finish loading', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = HostRepository();
    await tester.pumpWidget(SshApp(repo: repo));
    expect(find.text('Hosts'), findsOneWidget);
    await repo.load();
    await tester.pump();
    expect(find.text('No hosts yet. Tap + to add one.'), findsOneWidget);
  });
}
