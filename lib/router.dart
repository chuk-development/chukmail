import 'package:go_router/go_router.dart';

import 'features/compose/compose_page.dart';
import 'features/mailbox/mailbox_page.dart';
import 'features/mailbox/message_view_page.dart';
import 'features/settings/settings_page.dart';

GoRouter buildRouter() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const MailboxPage(),
        ),
        GoRoute(
          path: '/message/:id',
          builder: (_, st) => MessageViewPage(
            messageRowId: int.parse(st.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/compose',
          builder: (_, st) => ComposePage(
            accountId: st.uri.queryParameters['account'],
            toAddr: st.uri.queryParameters['to'],
            subject: st.uri.queryParameters['subject'],
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsPage(),
        ),
      ],
    );
