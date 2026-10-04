import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/session_store.dart';
import 'register_page.dart';
import 'widgets/dialogs.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      await showMessageDialog(context, '請輸入 email 與密碼');
      return;
    }
    setState(() => _busy = true);
    String? error;
    try {
      await context.read<SessionStore>().login(_email.text, _password.text);
    } on ApiException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);      // 先停掉按鈕上的轉圈,再顯示訊息
    if (error != null) await showMessageDialog(context, error, title: '登入失敗');
  }

  void _openRegister() {
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const RegisterPage()));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('登入')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            Icon(CupertinoIcons.creditcard, size: 56, color: CupertinoColors.systemBlue.resolveFrom(context)),
            const SizedBox(height: 12),
            Text('刷哪張卡最划算', textAlign: TextAlign.center,
                style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle.copyWith(fontSize: 26)),
            const SizedBox(height: 4),
            Text('輸入店名,幫你挑回饋最高的卡', textAlign: TextAlign.center, style: TextStyle(color: secondary)),
            const SizedBox(height: 24),
            CupertinoFormSection.insetGrouped(
              children: [
                CupertinoTextFormFieldRow(
                  controller: _email,
                  prefix: const Text('Email'),
                  placeholder: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                ),
                CupertinoTextFormFieldRow(
                  controller: _password,
                  prefix: const Text('密碼'),
                  placeholder: '密碼',
                  obscureText: true,
                  onFieldSubmitted: (_) => _login(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoButton.filled(
                onPressed: _busy ? null : _login,
                child: _busy ? const CupertinoActivityIndicator(color: CupertinoColors.white) : const Text('登入'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('還沒有帳號?', style: TextStyle(color: secondary)),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  onPressed: _busy ? null : _openRegister,
                  child: const Text('前往註冊'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
