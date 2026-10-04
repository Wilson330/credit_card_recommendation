import 'package:flutter/cupertino.dart';

/// 顯示一個只有「好」按鈕的訊息框,例如後端回傳的錯誤訊息。
Future<void> showMessageDialog(BuildContext context, String message, {String title = '無法完成'}) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('好'),
        ),
      ],
    ),
  );
}
