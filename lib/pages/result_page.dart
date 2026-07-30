import 'package:flutter/material.dart';

import '../models/reward_evaluation_result.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('推薦結果'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: results.isEmpty
            ? Center(
                child: Text('找不到 $merchantName 的可用推薦'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$merchantName 推薦卡片',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final result = results[index];

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${index + 1}. ${result.cardName}',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text('回饋：${result.rewardRate}%'),
                                const SizedBox(height: 8),
                                Text(
                                  '命中方案：${result.matchedTags.join('、')}',
                                ),
                                if (result.requiredAction != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '必要動作：${result.requiredAction}',
                                    style: const TextStyle(color: Colors.orange),
                                  ),
                                ],
                                if (result.constraints.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '限制條件：${result.constraints.join('、')}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}