import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/session_store.dart';
import 'widgets/dialogs.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const _minPasswordLength = 8;   // 與後端 backend/auth.py 一致

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  DateTime? _birthday;
  bool _busy = false;

  String get _birthdayText => _birthday == null
      ? ''
      : '${_birthday!.year}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}';

  Future<void> _pickBirthday() async {
    var picked = _birthday ?? DateTime(1995, 1, 1);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => Container(
        height: 300,
        color: CupertinoColors.systemBackground.resolveFrom(popupContext),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                onPressed: () => Navigator.of(popupContext).pop(),
                child: const Text('完成'),
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: picked,
                minimumDate: DateTime(1900),
                maximumDate: DateTime.now(),
                onDateTimeChanged: (value) => picked = value,
              ),
            ),
          ],
        ),
      ),
    );
    setState(() => _birthday = picked);
  }

  Future<void> _register() async {
    final problem = _validate();
    if (problem != null) {
      await showMessageDialog(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<SessionStore>().register(
            email: _email.text,
            password: _password.text,
            fullName: _name.text,
            birthday: _birthdayText,
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);    // 先停掉按鈕上的轉圈,再顯示訊息
      await showMessageDialog(context, e.message, title: '註冊失敗');
      return;
    }
    // 註冊後直接登入,回到最上層(AppRoot 會切換到首頁)
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String? _validate() {
    if (_email.text.trim().isEmpty || _password.text.isEmpty || _name.text.trim().isEmpty || _birthday == null) {
      return 'email、密碼、姓名、生日都是必填';
    }
    if (_password.text.length < _minPasswordLength) return '密碼至少要 $_minPasswordLength 個字元';
    return null;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('註冊')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            CupertinoFormSection.insetGrouped(
              footer: Text('生日用來判斷「慶生月」等生日當月的優惠', style: TextStyle(color: secondary)),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _email,
                  prefix: const Text('Email'),
                  placeholder: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                ),
                CupertinoTextFormFieldRow(
                  controller: _password,
                  prefix: const Text('密碼'),
                  placeholder: '至少 $_minPasswordLength 個字元',
                  obscureText: true,
                ),
                CupertinoTextFormFieldRow(
                  controller: _name,
                  prefix: const Text('姓名'),
                  placeholder: '姓名',
                ),
                CupertinoFormRow(
                  prefix: const Text('生日'),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _pickBirthday,
                    child: Text(_birthday == null ? '選擇日期' : _birthdayText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoButton.filled(
                onPressed: _busy ? null : _register,
                child: _busy ? const CupertinoActivityIndicator(color: CupertinoColors.white) : const Text('註冊並登入'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
