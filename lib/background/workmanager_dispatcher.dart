import 'package:workmanager/workmanager.dart';

import '../services/sync_service.dart';

const String kSyncTaskName = 'chukmail.periodicSync';
const String kSyncUniqueName = 'chukmail.periodicSync.unique';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await SyncService.syncAll();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundSync {
  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> schedule({int minutes = 15}) async {
    await Workmanager().registerPeriodicTask(
      kSyncUniqueName,
      kSyncTaskName,
      frequency: Duration(minutes: minutes < 15 ? 15 : minutes),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kSyncUniqueName);
  }
}
