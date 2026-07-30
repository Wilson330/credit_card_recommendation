import 'package:flutter/cupertino.dart';

import '../models/reward_evaluation_result.dart';
import 'widgets/card_thumbnail.dart';

class ResultPage extends StatelessWidget {
  final String merchantName;
  final List<RewardEvaluationResult> results;

  const ResultPage({
    super.key,
    required this.merchantName,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('推薦結果'),
      ),
      child: SafeArea(
        child: results.isEmpty
            ? Center(
                child: Text(
                  '找不到 $merchantName 的可用推薦',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '$merchantName 推薦卡片',
                    style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                  ),
                  const SizedBox(height: 16),
                  for (var index = 0; index < results.length; index++) ...[
                    _ResultCard(rank: index + 1, result: results[index]),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final int rank;
  final RewardEvaluationResult result;

  const _ResultCard({required this.rank, required this.result});

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      '#$rank ${result.cardName}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${result.rewardRate}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: CupertinoColors.systemBlue.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '命中方案：${result.matchedTags.join('、')}',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                if (result.requiredAction != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '必要動作：${result.requiredAction}',
                    style: TextStyle(
                      color: CupertinoColors.systemOrange.resolveFrom(context),
                    ),
                  ),
                ],
                if (result.constraints.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '限制條件：${result.constraints.join('、')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
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
