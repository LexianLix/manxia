import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/frame_budget.dart';

void main() {
  test('sustained slow frames shed optical work while brief spikes do not', () {
    final budget = FrameBudget();
    addTearDown(budget.dispose);
    for (var i = 0; i < 19; i++) {
      budget.observe(3000, 5000);
    }
    budget.observe(5000, 45000);
    expect(budget.value, 0);
    for (var i = 0; i < 20; i++) {
      budget.observe(2000, 22000);
    }
    expect(budget.value, 1);
    for (var i = 0; i < 20; i++) {
      budget.observe(40000, 3000);
    }
    expect(budget.value, 2);
    for (var i = 0; i < 599; i++) {
      budget.observe(4000, 5000);
    }
    expect(budget.value, 2);
    budget.observe(4000, 5000);
    expect(budget.value, 1);
    for (var i = 0; i < 600; i++) {
      budget.observe(4000, 5000);
    }
    expect(budget.value, 0);
  });
  test(
    'backgrounding discards partial windows and stale recovery evidence',
    () {
      final budget = FrameBudget();
      addTearDown(budget.dispose);
      for (var i = 0; i < 19; i++) {
        budget.observe(45000, 2000);
      }
      budget.pause();
      budget.observe(45000, 2000);
      expect(budget.value, 0);
      for (var i = 0; i < 19; i++) {
        budget.observe(2000, 45000);
      }
      expect(budget.value, 1);
    },
  );
}
