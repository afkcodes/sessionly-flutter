// Driver for `flutter drive` runs of the integration_test suites. It writes any
// `binding.reportData` the test set (e.g. the perf frame stats) to
// build/integration_response_data.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
