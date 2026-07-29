/// Typed-prop validation for the `revenue/purchase` event, mirroring
/// `packages/core/src/protocol/v1/revenue-props.ts` exactly (Rule 2.1).
///
/// Unlike ordinary props (bounded only by shape/size in `limits.dart`), a
/// revenue event's props are validated on the wire: a money-bearing record is
/// rejected — not accepted and flagged — when `amount_minor` / `currency` /
/// `provider` are malformed. Additive-only (Rule 2.3): providers append.
library;

import 'package:sessionly_flutter/src/protocol/errors.dart';
import 'package:sessionly_flutter/src/protocol/parse.dart';

/// Payment providers a revenue event may originate from (bounded vocabulary).
const Set<String> revenueProviders = {'stripe', 'revenuecat', 'manual'};

/// Upper bound on `amount_minor` (minor currency units — cents/paise).
const int revenueAmountMinorMax = 1000000000000;

/// Max length of an optional `product_id` string.
const int revenueProductIdMaxLength = 256;

/// ISO-4217 currency code: exactly three uppercase Latin letters (e.g. `USD`).
final RegExp iso4217Regex = RegExp(r'^[A-Z]{3}$');

/// Validates the typed fields of a `revenue/purchase` props map at [path],
/// throwing a [SessionlyProtocolError] at the offending child path on any
/// violation. The generic shape/size caps are enforced separately by
/// `validateProps`; this pins only the revenue-specific fields.
void validateRevenueProps(Map<String, Object?> props, String path) {
  final amount = props['amount_minor'];
  // `4.99` decodes to a Dart double, not int → rejected (minor units only).
  if (amount is! int || amount < 0 || amount > revenueAmountMinorMax) {
    throw SessionlyProtocolError(
      'amount_minor must be an integer in [0, $revenueAmountMinorMax]',
      path: childPath(path, 'amount_minor'),
    );
  }

  final currency = requireString(props, 'currency', path);
  if (!iso4217Regex.hasMatch(currency)) {
    throw SessionlyProtocolError(
      'currency must be an ISO-4217 uppercase 3-letter code',
      path: childPath(path, 'currency'),
    );
  }

  requireEnum(props, 'provider', revenueProviders, path);

  // product_id is nullish: absent or null are fine; a present non-null value
  // must be a non-empty string within the length cap.
  if (props.containsKey('product_id') && props['product_id'] != null) {
    final productId = requireString(props, 'product_id', path);
    if (productId.length > revenueProductIdMaxLength) {
      throw SessionlyProtocolError(
        'product_id may not exceed $revenueProductIdMaxLength characters',
        path: childPath(path, 'product_id'),
      );
    }
  }

  // recurring is optional: absent is fine; present must be a boolean.
  if (props.containsKey('recurring') && props['recurring'] is! bool) {
    throw SessionlyProtocolError(
      'recurring must be a boolean',
      path: childPath(path, 'recurring'),
    );
  }
}
