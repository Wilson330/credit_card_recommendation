import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../constants/popular_merchants.dart';
import '../state/search_history_store.dart';
import '../state/session_store.dart';
import '../state/user_cards_store.dart';
import 'my_cards_page.dart';
import 'result_page.dart';
import 'widgets/card_thumbnail.dart';
import 'widgets/dialogs.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _merchantController = TextEditingController();
  final _searchFocusNode = FocusNode();

  bool _showSuggestions = false;
  List<MerchantSuggestion> _suggestions = const [];
  bool _searching = false;

  // 自動補全:同時只允許一個請求在途中;結果回來時文字變了,就用最新的文字再送一次
  // (docs/DB_DESIGN.md 7.1)
  bool _suggestInFlight = false;
  String? _lastSuggestedQuery;

  @override
  void initState() {
    super.initState();
    // 用自己的 listener 驅動,而不是 RawAutocomplete 的 optionsBuilder:
    // 後者只在文字改變時重算,單純取得焦點時不會顯示建議(見 git 紀錄)
    _merchantController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchChanged);
  }

  ApiClient get _api => context.read<ApiClient>();

  void _onSearchChanged() {
    if (!_searchFocusNode.hasFocus) {
      if (_showSuggestions) setState(() => _showSuggestions = false);
      return;
    }
    if (!_showSuggestions) setState(() => _showSuggestions = true);

    // 輸入法還在組字(例如注音 ㄉㄧㄥˇ 尚未選字)時不送查詢
    final composing = _merchantController.value.composing;
    if (composing.isValid && !composing.isCollapsed) return;

    final query = _merchantController.text.trim();
    if (query.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      _lastSuggestedQuery = null;
      return;
    }
    _requestSuggestions();
  }

  Future<void> _requestSuggestions() async {
    if (_suggestInFlight) return;      // 回來後會檢查文字是否變了
    final query = _merchantController.text.trim();
    if (query.isEmpty || query == _lastSuggestedQuery) return;

    _suggestInFlight = true;
    _lastSuggestedQuery = query;
    try {
      final result = await _api.suggest(query);
      if (mounted) setState(() => _suggestions = result);
    } on ApiException {
      // 自動補全失敗不打擾使用者,按搜尋時才顯示錯誤
    } finally {
      _suggestInFlight = false;
    }
    if (mounted && _searchFocusNode.hasFocus && _merchantController.text.trim() != query) {
      _requestSuggestions();
    }
  }

  void _openMyCardsPage() {
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const MyCardsPage()));
  }

  Future<void> _search({required String label, required Future<Recommendation> Function() request}) async {
    final store = context.read<UserCardsStore>();
    if (!store.hasCards || _searching) return;

    context.read<SearchHistoryStore>().recordSearch(label);
    _merchantController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _showSuggestions = false;
      _searching = true;
    });

    final Recommendation recommendation;
    try {
      recommendation = await request();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);    // 先停掉按鈕上的轉圈,再顯示訊息
      if (!e.isUnauthorized) await showMessageDialog(context, e.message, title: '查詢失敗');
      return;
    }
    if (!mounted) return;
    setState(() => _searching = false);
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (_) => ResultPage(query: label, recommendation: recommendation),
    ));
  }

  void _searchByText(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;
    _search(label: query, request: () => _api.recommendByQuery(query));
  }

  void _searchBySuggestion(MerchantSuggestion s) {
    _search(label: s.name, request: () => _api.recommendByMerchantId(s.merchantId));
  }

  Future<void> _confirmLogout() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出嗎?'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<SessionStore>().logout();
  }

  Widget _buildCardStrip(List<UserCard> userCards) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: userCards.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => CardThumbnail(cardId: userCards[index].cardId, width: 70),
      ),
    );
  }

  Widget _buildSuggestionsPanel(BuildContext context) {
    final query = _merchantController.text.trim();

    // TextFieldTapRegion + 單一捲動區:兩者都是點選建議能正確觸發的必要條件(見 git 紀錄)
    return TextFieldTapRegion(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: query.isEmpty ? _buildGroupedSuggestions(context) : _buildFlatSuggestions(context),
      ),
    );
  }

  Widget _buildGroupedSuggestions(BuildContext context) {
    final history = context.watch<SearchHistoryStore>().history;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (history.isNotEmpty) ...[
          _sectionHeader(context, '歷史查詢'),
          for (final item in history)
            CupertinoListTile(
              leading: const Icon(CupertinoIcons.clock, size: 20),
              title: Text(item),
              onTap: () => _searchByText(item),
            ),
        ],
        _sectionHeader(context, '熱門商家'),
        for (final item in PopularMerchants.suggestions)
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.flame, size: 20),
            title: Text(item),
            onTap: () => _searchByText(item),
          ),
      ],
    );
  }

  Widget _buildFlatSuggestions(BuildContext context) {
    if (_suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '找不到符合的商家,仍可直接按 Enter 搜尋',
          style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context)),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in _suggestions)
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.bag, size: 20),
            title: Text(s.name),
            onTap: () => _searchBySuggestion(s),
          ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label, style: TextStyle(fontSize: 13, color: CupertinoColors.secondaryLabel.resolveFrom(context))),
    );
  }

  Widget _buildSyncError(BuildContext context, UserCardsStore store) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemOrange.resolveFrom(context).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle, color: CupertinoColors.systemOrange.resolveFrom(context)),
          const SizedBox(width: 8),
          Expanded(child: Text('無法同步卡片:${store.error}')),
          CupertinoButton(padding: EdgeInsets.zero, onPressed: store.refresh, child: const Text('重試')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _merchantController.removeListener(_onSearchChanged);
    _searchFocusNode.removeListener(_onSearchChanged);
    _merchantController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();
    final user = context.watch<SessionStore>().user;
    final userCards = store.userCards;
    final hasCards = store.hasCards;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(padding: EdgeInsets.zero, onPressed: _confirmLogout, child: const Text('登出')),
        middle: Text(user == null ? '刷哪張卡' : '嗨,${user.fullName}'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _openMyCardsPage,
          child: const Icon(CupertinoIcons.creditcard),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (store.error != null) _buildSyncError(context, store),
              Text(
                hasCards ? '已設定 ${userCards.length} 張卡片' : (store.isLoading ? '正在載入卡片…' : '尚未設定卡片'),
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
              ),
              if (hasCards) ...[
                const SizedBox(height: 12),
                _buildCardStrip(userCards),
              ],
              const SizedBox(height: 16),
              if (!hasCards)
                CupertinoButton.filled(onPressed: _openMyCardsPage, child: const Text('設定我的卡片'))
              else
                CupertinoButton(padding: EdgeInsets.zero, onPressed: _openMyCardsPage, child: const Text('管理我的卡片')),
              const SizedBox(height: 24),
              CupertinoTextField(
                controller: _merchantController,
                focusNode: _searchFocusNode,
                placeholder: '輸入商家名稱,例如:全家、Uber Eats、UNIQLO',
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(CupertinoIcons.search, size: 18, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                ),
                onSubmitted: _searchByText,
              ),
              if (_showSuggestions) _buildSuggestionsPanel(context),
              const SizedBox(height: 16),
              if (hasCards)
                CupertinoButton.filled(
                  onPressed: _searching ? null : () => _searchByText(_merchantController.text),
                  child: _searching
                      ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                      : const Text('開始推薦'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
