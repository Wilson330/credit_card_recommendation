import 'package:flutter/cupertino.dart';

import '../api/models.dart';
import 'widgets/card_thumbnail.dart';

/// 各卡片都有的通用說明,不需要每張卡都重複顯示。
const _genericNote = '實際回饋依當期公告為準';

class ResultPage extends StatelessWidget {
  /// 使用者輸入或點選的文字。
  final String query;
  final Recommendation recommendation;

  const ResultPage({super.key, required this.query, required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final results = recommendation.results;
    final title = recommendation.merchantName ?? query;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('推薦結果')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('$title 推薦卡片', style: CupertinoTheme.of(context).textTheme.navTitleTextStyle),
            if (recommendation.merchantName != null && recommendation.merchantName != query) ...[
              const SizedBox(height: 4),
              Text('依「$query」找到這家店', style: TextStyle(fontSize: 13, color: secondary)),
            ],
            if (!recommendation.merchantFound && recommendation.message != null) ...[
              const SizedBox(height: 12),
              _Banner(message: recommendation.message!),
            ],
            const SizedBox(height: 16),
            if (results.isEmpty)
              Text('你還沒有設定卡片,先到「我的卡片」新增', style: TextStyle(color: secondary))
            else
              for (var i = 0; i < results.length; i++) ...[
                _ResultCard(rank: i + 1, result: results[i]),
                const SizedBox(height: 12),
              ],
            if (results.isNotEmpty)
              Text(_genericNote, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: secondary)),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;

  const _Banner({required this.message});

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.systemOrange.resolveFrom(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(CupertinoIcons.info, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final int rank;
  final CardRecommendation result;

  const _ResultCard({required this.rank, required this.result});

  @override
  Widget build(BuildContext context) {
    final notes = result.notes.where((n) => n != _genericNote).toList();
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardThumbnail(cardId: result.cardId, width: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('#$rank ${result.cardName}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      '${result.rateText}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.systemBlue.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(result.bankName, style: TextStyle(fontSize: 13, color: secondary)),
                const SizedBox(height: 6),
                Text(result.isGeneral ? '${result.schemeName}(不需要切換方案)' : '方案:${result.schemeName}',
                    style: TextStyle(color: secondary)),
                if (result.requiredAction != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    result.requiredAction!,
                    style: TextStyle(color: CupertinoColors.systemOrange.resolveFrom(context), fontWeight: FontWeight.w600),
                  ),
                ],
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    notes.join('\n'),
                    style: TextStyle(fontSize: 12, color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
