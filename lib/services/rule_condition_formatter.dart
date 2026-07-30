import '../models/rule_condition.dart';

class RuleConditionFormatter {
  static String format(RuleCondition condition) {
    final parts = <String>[];

    // selectedProgram 已由 UI badge 顯示，這裡不重複輸出
    if (condition.requiresManualSelection) {
      // 保留 requiresManualSelection 的語意給未來擴充，
      // 但目前不另外輸出文字，避免和 badge 重複。
    }

    if (condition.japanOnly) {
      parts.add('限日本消費');
    }

    if (condition.physicalStoreOnly) {
      parts.add('限實體門市');
    }

    if (condition.requiresApplePay && condition.requiresGooglePay) {
      parts.add('需使用 Apple Pay / Google Pay');
    } else if (condition.requiresApplePay) {
      parts.add('需使用 Apple Pay');
    } else if (condition.requiresGooglePay) {
      parts.add('需使用 Google Pay');
    }

    if (condition.requiresRegistration) {
      parts.add('需登錄活動');
    }

    if (condition.designatedMerchantOnly) {
      parts.add('限指定通路');
    }

    if (condition.installmentExcluded) {
      parts.add('不含分期交易');
    }

    if (condition.newCustomerOnly) {
      parts.add('限新戶');
    }

    if (condition.requiredLevel != null && condition.requiredLevel!.isNotEmpty) {
      parts.add(condition.requiredLevel!);
    }

    if (condition.merchantGroup != null && condition.merchantGroup!.isNotEmpty) {
      parts.add('通路群組：${condition.merchantGroup!}');
    }

    if (condition.paymentMethodNote != null &&
        condition.paymentMethodNote!.isNotEmpty) {
      parts.add(condition.paymentMethodNote!);
    }

    if (parts.isEmpty) {
      return '一般消費條件';
    }

    return parts.join(' ・ ');
  }
}