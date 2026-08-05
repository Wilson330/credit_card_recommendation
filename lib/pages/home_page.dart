import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../constants/popular_merchants.dart';
import '../models/merchant_query_context.dart';
import '../models/user_card_bundle.dart';
import '../services/merchant_resolver.dart';
import '../services/merchant_suggestion_index.dart';
import '../services/recommendation_orchestrator.dart';
import '../state/search_history_store.dart';
import '../state/user_cards_store.dart';
import 'my_cards_page.dart';
import 'result_page.dart';
import 'widgets/card_thumbnail.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _merchantController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _orchestrator = RecommendationOrchestrator();
  final _suggestionIndex = MerchantSuggestionIndex();
  final _merchantResolver = MerchantResolver();

  bool _showSuggestions = false;
  List<String> _currentSuggestions = const [];

  @override
  void initState() {
    super.initState();
    // Driven by our own listeners (not RawAutocomplete's built-in lazy
    // optionsBuilder, which only recomputes on a text VALUE change and
    // does nothing on bare focus — see git history for why).
    _merchantController.addListener(_recomputeSuggestions);
    _searchFocusNode.addListener(_recomputeSuggestions);
  }

  void _recomputeSuggestions() {
    if (!_searchFocusNode.hasFocus) {
      if (_showSuggestions) {
        setState(() => _showSuggestions = false);
      }
      return;
    }

    final query = _merchantController.text.trim();
    final suggestions = query.isEmpty
        ? _historyAndPopular()
        : _suggestionIndex.suggestionsFor(query);

    setState(() {
      _showSuggestions = true;
      _currentSuggestions = suggestions;
    });
  }

  List<String> _historyAndPopular() {
    final history = context.read<SearchHistoryStore>().history;
    final seen = <String>{};
    return [...history, ...PopularMerchants.suggestions]
        .where((item) => seen.add(item))
        .toList();
  }

  void _selectSuggestion(String value) {
    _merchantController.text = value;
    _handleSearch(value);
  }

  void _openMyCardsPage() {
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const MyCardsPage()),
    );
  }

  void _handleSearch(String rawMerchantName) {
    final merchantName = rawMerchantName.trim();
    if (merchantName.isEmpty) return;

    final store = context.read<UserCardsStore>();
    final userCards = store.userCards;
    if (userCards.isEmpty) return;

    context.read<SearchHistoryStore>().recordSearch(merchantName);

    final merchantContext = MerchantQueryContext(
      merchantName: merchantName,
      merchantTags: _merchantResolver.tagsFor(merchantName),
    );

    final results = _orchestrator.evaluate(
      merchantContext: merchantContext,
      userCards: userCards,
    );

    _merchantController.clear();
    _searchFocusNode.unfocus();
    setState(() => _showSuggestions = false);

    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ResultPage(
          merchantName: merchantName,
          results: results,
        ),
      ),
    );
  }

  Widget _buildCardStrip(List<UserCardBundle> userCards) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: userCards.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) =>
            CardThumbnail(cardId: userCards[index].walletCard.cardId, width: 70),
      ),
    );
  }

  Widget _buildSuggestionsPanel(BuildContext context) {
    final query = _merchantController.text.trim();

    // TextFieldTapRegion + a single non-nested scroll region: see git
    // history on this file for why both matter for tap reliability.
    return TextFieldTapRegion(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: query.isEmpty
            ? _buildGroupedSuggestions(context)
            : _buildFlatSuggestions(context),
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
          ...history.map(
            (item) => CupertinoListTile(
              leading: const Icon(CupertinoIcons.clock, size: 20),
              title: Text(item),
              onTap: () => _selectSuggestion(item),
            ),
          ),
        ],
        _sectionHeader(context, '熱門商家'),
        ...PopularMerchants.suggestions.map(
          (item) => CupertinoListTile(
            leading: const Icon(CupertinoIcons.flame, size: 20),
            title: Text(item),
            onTap: () => _selectSuggestion(item),
          ),
        ),
      ],
    );
  }

  Widget _buildFlatSuggestions(BuildContext context) {
    if (_currentSuggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '找不到符合的商家，仍可直接按 Enter 搜尋',
          style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context)),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in _currentSuggestions)
          CupertinoListTile(
            leading: const Icon(CupertinoIcons.bag, size: 20),
            title: Text(option),
            onTap: () => _selectSuggestion(option),
          ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _merchantController.removeListener(_recomputeSuggestions);
    _searchFocusNode.removeListener(_recomputeSuggestions);
    _merchantController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UserCardsStore>();
    final userCards = store.userCards;
    final hasCards = store.hasCards;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('My Cards'),
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
              Text(
                hasCards ? '已設定 ${userCards.length} 張卡片' : '尚未設定卡片',
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
              ),
              if (hasCards) ...[
                const SizedBox(height: 12),
                _buildCardStrip(userCards),
              ],
              const SizedBox(height: 16),
              if (!hasCards)
                CupertinoButton.filled(
                  onPressed: _openMyCardsPage,
                  child: const Text('設定我的卡片'),
                )
              else
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _openMyCardsPage,
                  child: const Text('管理我的卡片'),
                ),
              const SizedBox(height: 24),
              CupertinoTextField(
                controller: _merchantController,
                focusNode: _searchFocusNode,
                placeholder: '輸入商家名稱，例如：全家、Uber Eats、UNIQLO',
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.search,
                    size: 18,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                onSubmitted: _handleSearch,
              ),
              if (_showSuggestions) _buildSuggestionsPanel(context),
              const SizedBox(height: 16),
              if (hasCards)
                CupertinoButton.filled(
                  onPressed: () => _handleSearch(_merchantController.text),
                  child: const Text('開始推薦'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
