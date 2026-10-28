import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/shelf_orbit.dart';

void main() {
  test('ring wraps without a position, depth or cover-size discontinuity', () {
    for (final count in [2, 3, 5, 9]) {
      final before = ShelfOrbitPose(count / 2 - .00001, count);
      final after = ShelfOrbitPose(-count / 2 + .00001, count);
      expect(before.horizontal, closeTo(after.horizontal, .0001));
      expect(before.vertical, closeTo(after.vertical, .0001));
      expect(before.scale, closeTo(after.scale, .0001));
      expect(before.yaw, closeTo(after.yaw, .0001));
    }
    final side = ShelfOrbitPose(1, 7);
    expect(side.vertical, lessThan(8));
    expect(side.scale, greaterThan(.9));
  });
  test(
    'strong flick coasts, then settles with continuous position and velocity',
    () {
      for (final speed in [-18.0, 18.0]) {
        final glide = ShelfGlideSimulation(5000.3, speed);
        expect(glide.coastDuration, greaterThan(.7));
        expect((glide.x(.6) - glide.x(.2)) * speed.sign, greaterThan(2));
        final join = glide.coastDuration;
        expect(glide.x(join - .00001), closeTo(glide.x(join), .001));
        expect(glide.dx(join - .00001), closeTo(glide.dx(join), .001));
        expect(glide.x(5), glide.target);
        expect(glide.dx(5), 0);
        expect(glide.isDone(5), isTrue);
      }
    },
  );
  test('slow release settles close by without adding a long coast', () {
    final glide = ShelfGlideSimulation(23.2, .5);
    expect(glide.coastDuration, 0);
    expect(glide.target, 23);
    expect(glide.x(0), closeTo(23.2, .0001));
  });
}
