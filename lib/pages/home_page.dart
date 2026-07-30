import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/popular_merchants.dart';
import '../models/merchant_query_context.dart';
import '../services/merchant_suggestion_index.dart';
import '../services/recommendation_orchestrator.dart';
import '../state/search_history_store.dart';
import '../state/user_cards_store.dart';
import 'my_cards_page.dart';
import 'result_page.dart';

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

  bool _showSuggestions = false;
  List<String> _currentSuggestions = const [];

  @override
  void initState() {
    super.initState();
    // Driven by our own listeners (not RawAutocomplete's built-in lazy
    // optionsBuilder, which only recomputes on a text VALUE change and
    // does nothing on bare focus — see home_page.dart git history for why).
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
      MaterialPageRoute(
        builder: (_) => const MyCardsPage(),
      ),
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
    );

    final results = _orchestrator.evaluate(
      merchantContext: merchantContext,
      userCards: userCards,
    );

    _merchantController.clear();
    _searchFocusNode.unfocus();
    setState(() => _showSuggestions = false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultPage(
          merchantName: merchantName,
          results: results,
        ),
      ),
    );
  }

  Widget _buildSuggestionsPanel(BuildContext context) {
    final query = _merchantController.text.trim();

    // Without this, EditableText's default onTapOutside fires on
    // PointerDownEvent (see Flutter SDK editable_text.dart
    // _defaultOnTapOutside) and unfocuses the field — which hides this
    // panel via _recomputeSuggestions() before the ListTile's own tap
    // gesture finishes resolving, so taps on suggestions silently do
    // nothing. RawAutocomplete's own options view wraps itself in the
    // same widget for the same reason (see Flutter SDK autocomplete.dart).
    //
    // This is intentionally NOT its own scrollable (no ListView here) even
    // though it used to be one — nesting a second vertical scrollable
    // inside the page's SingleChildScrollView makes ListTile.onTap
    // unreliable with a mouse: any few-pixel drift between pointer-down
    // and pointer-up (routine with a mouse, never happens with a
    // synthetic test tap) can make the inner scrollable's drag recognizer
    // win the gesture arena instead of the tap, silently swallowing the
    // click. Flattening to one scroll region (the page itself) removes
    // the competing recognizer entirely.
    return TextFieldTapRegion(
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: query.isEmpty
            ? _buildGroupedSuggestions(context)
            : _buildFlatSuggestions(),
      ),
    );
  }

  Widget _buildGroupedSuggestions(BuildContext context) {
    final history = context.watch<SearchHistoryStore>().history;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (history.isNotEmpty) ...[
          _sectionHeader(context, '歷史查詢'),
          ...history.map(
            (item) => ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 18),
              title: Text(item),
              onTap: () => _selectSuggestion(item),
            ),
          ),
        ],
        _sectionHeader(context, '熱門商家'),
        ...PopularMerchants.suggestions.map(
          (item) => ListTile(
            dense: true,
            leading: const Icon(Icons.local_fire_department, size: 18),
            title: Text(item),
            onTap: () => _selectSuggestion(item),
          ),
        ),
      ],
    );
  }

  Widget _buildFlatSuggestions() {
    if (_currentSuggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('找不到符合的商家，仍可直接按 Enter 搜尋'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in _currentSuggestions)
          ListTile(
            dense: true,
            leading: const Icon(Icons.storefront, size: 18),
            title: Text(option),
            onTap: () => _selectSuggestion(option),
          ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Colors.grey),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cards'),
        actions: [
          IconButton(
            onPressed: _openMyCardsPage,
            icon: const Icon(Icons.credit_card),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasCards ? '已設定 ${userCards.length} 張卡片' : '尚未設定卡片',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (hasCards)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Debug: 目前卡片狀態',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  ...userCards.map(
                    (c) => Text(
                      '- ${c.walletCard.cardName} (${c.walletCard.cardId})',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _openMyCardsPage,
              child: const Text('設定我的卡片'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _merchantController,
              focusNode: _searchFocusNode,
              decoration: const InputDecoration(
                labelText: '輸入商家名稱',
                hintText: '例如：全家、Uber Eats、UNIQLO',
              ),
              onSubmitted: _handleSearch,
            ),
            if (_showSuggestions) _buildSuggestionsPanel(context),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: hasCards ? () => _handleSearch(_merchantController.text) : null,
              child: const Text('開始推薦'),
            ),
          ],
        ),
      ),
    );
  }
}
