import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class AddressActions {
  static Future<void> show(
    BuildContext context, {
    required String email,
    String? name,
    required String composeAccountId,
    VoidCallback? onShowFullHeaders,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final messenger = ScaffoldMessenger.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  child: Text(((name?.isNotEmpty == true ? name! : email)
                          .characters
                          .first)
                      .toUpperCase()),
                ),
                title: Text(name?.isNotEmpty == true ? name! : email),
                subtitle: name?.isNotEmpty == true ? Text(email) : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy email address'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: email));
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Copied $email'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              if (name?.isNotEmpty == true)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Copy name'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: name!));
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Copied $name'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('New mail to this address'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  context.push(
                      '/compose?account=$composeAccountId&to=${Uri.encodeQueryComponent(email)}');
                },
              ),
              if (onShowFullHeaders != null)
                ListTile(
                  leading: const Icon(Icons.code_outlined),
                  title: const Text('Show full headers'),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    onShowFullHeaders();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
