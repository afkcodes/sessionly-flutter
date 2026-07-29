// The four demo screens. Every interactive target carries a stable ValueKey so
// the SDK's content-free tap identity is meaningful, and the home screen offers
// a rage-tap target and a dead (non-interactive) zone so the frustration
// detectors have something to fire on during the scripted journey.
import 'package:flutter/material.dart';
import 'package:sessionly_flutter/sessionly_flutter.dart';

/// Route names — kept in one place so the perf journey and the navigator
/// observer agree on the `screen` labels.
abstract final class Routes {
  static const String home = '/';
  static const String list = '/list';
  static const String form = '/form';
  static const String heavy = '/heavy';
}

/// Home: navigation buttons, a custom-event button, a rage target, dead zone.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessionly Demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Home', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 16),
          ElevatedButton(
            key: const ValueKey('go_list'),
            onPressed: () => Navigator.pushNamed(context, Routes.list),
            child: const Text('Open list screen'),
          ),
          ElevatedButton(
            key: const ValueKey('go_form'),
            onPressed: () => Navigator.pushNamed(context, Routes.form),
            child: const Text('Open form screen'),
          ),
          ElevatedButton(
            key: const ValueKey('go_heavy'),
            onPressed: () => Navigator.pushNamed(context, Routes.heavy),
            child: const Text('Open heavy (animated) screen'),
          ),
          const Divider(height: 32),
          ElevatedButton(
            key: const ValueKey('track_custom'),
            onPressed: () => Sessionly.track(
              'demo_button_pressed',
              props: {'source': 'home'},
            ),
            child: const Text('Fire a custom event'),
          ),
          const SizedBox(height: 8),
          // Interactive but inert — tap it fast 3x to trigger a rage_tap.
          ElevatedButton(
            key: const ValueKey('rage_target'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
            ),
            onPressed: () {},
            child: const Text('Rage-tap me (does nothing)'),
          ),
          const SizedBox(height: 8),
          // Non-interactive region — a tap here is a dead_tap.
          Container(
            key: const ValueKey('dead_zone'),
            height: 80,
            alignment: Alignment.center,
            color: Colors.grey.shade300,
            child: const Text('Dead zone (no handler)'),
          ),
          const SizedBox(height: 8),
          // Records a forced-slow request (4200 ms > default 3000 ms threshold)
          // through the public tracker. The URL deliberately carries userinfo
          // credentials and a query string with PII — the SDK must strip BOTH
          // before the host/path leave the device (Rule 7.1).
          ElevatedButton(
            key: const ValueKey('slow_http'),
            onPressed: () => Sessionly.httpTracker.recordRequest(
              Uri.parse(
                'https://user:secret@api.example.com/v1/checkout/session'
                '?token=abc123&email=user@example.com',
              ),
              'POST',
              200,
              4200,
            ),
            child: const Text('Record a slow HTTP request'),
          ),
        ],
      ),
    );
  }
}

/// A long scrollable list — the target of the scroll portion of the journey.
class ListScreen extends StatelessWidget {
  const ListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List')),
      body: ListView.builder(
        key: const ValueKey('demo_list'),
        itemCount: 200,
        itemBuilder: (context, i) => ListTile(
          key: ValueKey('row_$i'),
          leading: CircleAvatar(child: Text('$i')),
          title: Text('Item #$i'),
          subtitle: const Text('Scrollable content for the perf journey'),
          onTap: () => Sessionly.track('list_item_tapped', props: {'index': i}),
        ),
      ),
    );
  }
}

/// A form with text fields — exercises input focus/abandon without leaking
/// values. Each field carries an explicit `Semantics` label (the ONLY identity
/// the SDK reads); the entered text and even its length never leave the device.
/// The fields use explicit controllers, the real-app pattern (a controller-less
/// TextField's internal controller can be swapped under state restoration).
class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  // Name/email start with content (a prefilled/edit form) so their abandon
  // reports had_input=true; notes starts empty so focusing then leaving it
  // reports had_input=false. This drives both had_input branches from genuine
  // controller state — a physical device's real IME owns the input connection,
  // so `enterText` can't reliably land text on-device. Only the boolean
  // (any-text-present) leaves the device — never the content or its length.
  final _name = TextEditingController(text: 'Ada Lovelace');
  final _email = TextEditingController(text: 'ada@example.com');
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Form')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: 'name_field',
              textField: true,
              child: TextField(
                key: const ValueKey('field_name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'email_field',
              textField: true,
              child: TextField(
                key: const ValueKey('field_email'),
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'notes_field',
              textField: true,
              child: TextField(
                key: const ValueKey('field_notes'),
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              key: const ValueKey('submit_form'),
              onPressed: () => Sessionly.track('form_submitted'),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A continuously-animating screen — a steady stream of frames so the frame
/// timing surface (and any added jank) is exercised.
class HeavyScreen extends StatefulWidget {
  const HeavyScreen({super.key});

  @override
  State<HeavyScreen> createState() => _HeavyScreenState();
}

class _HeavyScreenState extends State<HeavyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Heavy')),
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Transform.rotate(
              angle: _controller.value * 6.28318,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 24; i++)
                    Container(
                      width: 40,
                      height: 40,
                      color: Color.lerp(
                        Colors.blue,
                        Colors.purple,
                        (i + _controller.value * 24) % 24 / 24,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
