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
          builder: (_, st) {
            final extra = st.extra;
            if (extra is ComposeExtra) {
              return ComposePage(
                accountId: extra.accountId ?? st.uri.queryParameters['account'],
                toAddr: extra.toAddr ?? st.uri.queryParameters['to'],
                ccAddr: extra.ccAddr,
                subject: extra.subject ?? st.uri.queryParameters['subject'],
                quoteBody: extra.quoteBody,
                inReplyTo: extra.inReplyTo,
                references: extra.references,
                isForward: extra.isForward,
              );
            }
            return ComposePage(
              accountId: st.uri.queryParameters['account'],
              toAddr: st.uri.queryParameters['to'],
              subject: st.uri.queryParameters['subject'],
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsPage(),
        ),
      ],
    );
