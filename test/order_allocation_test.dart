import 'package:flutter_test/flutter_test.dart';
import 'package:quick_ledger/domain/order_allocation.dart';

void main() {
  group('whole TWD allocation', () {
    test('Uber Eats example excludes self by default and reconciles', () {
      final result = allocateWholeTwd(
        itemAmountsMinor: const [13700, 16800, 16800, 20600],
        isSelf: const [true, false, false, false],
        deliveryFeeMinor: 3500,
        serviceFeeMinor: 5500,
        discountMinor: 13300,
        includeSelfInDeliveryFee: false,
        includeSelfInServiceFee: false,
        discountEligible: const [false, true, true, true],
      );

      expect(result.feeShares, const [0, 3100, 3000, 2900]);
      expect(result.collectionFeeShares, const [0, 3100, 3100, 3100]);
      expect(result.discountShares, const [0, 4500, 4400, 4400]);
      expect(result.actualDues, const [13700, 15400, 15400, 19100]);
      expect(result.suggestedDues, const [13700, 15400, 15500, 19300]);
      expect(result.actualDues.reduce((a, b) => a + b), 63600);
      expect(result.suggestedDues.reduce((a, b) => a + b), 63900);
    });

    test('largest remainder uses participant order as stable tie breaker', () {
      final result = allocateWholeTwd(
        itemAmountsMinor: const [10000, 10000, 10000],
        isSelf: const [true, false, false],
        deliveryFeeMinor: 100,
        serviceFeeMinor: 0,
        discountMinor: 100,
        includeSelfInDeliveryFee: true,
        includeSelfInServiceFee: true,
        discountEligible: const [true, true, true],
      );

      expect(result.feeShares, const [100, 0, 0]);
      expect(result.collectionFeeShares, const [100, 100, 100]);
      expect(result.discountShares, const [100, 0, 0]);
    });

    test('rounds each collection fee up while preserving exact card cost', () {
      final result = allocateWholeTwd(
        itemAmountsMinor: const [15000, 16000, 16000, 16000, 16000],
        isSelf: const [true, false, false, false, false],
        deliveryFeeMinor: 0,
        serviceFeeMinor: 1100,
        discountMinor: 0,
        includeSelfInDeliveryFee: false,
        includeSelfInServiceFee: false,
        discountEligible: const [false, false, false, false, false],
      );

      expect(result.feeShares, const [0, 300, 300, 300, 200]);
      expect(result.collectionFeeShares, const [0, 300, 300, 300, 300]);
      expect(result.actualDues, const [15000, 16300, 16300, 16300, 16200]);
      expect(result.suggestedDues, const [15000, 16300, 16300, 16300, 16300]);
    });

    test(
      'keeps ceil-each collection rule for twenty dollars and six people',
      () {
        final result = allocateWholeTwd(
          itemAmountsMinor: const [0, 0, 0, 0, 0, 0],
          isSelf: const [false, false, false, false, false, false],
          deliveryFeeMinor: 0,
          serviceFeeMinor: 2000,
          discountMinor: 0,
          includeSelfInDeliveryFee: false,
          includeSelfInServiceFee: false,
          discountEligible: const [false, false, false, false, false, false],
        );

        expect(result.feeShares, const [400, 400, 300, 300, 300, 300]);
        expect(result.collectionFeeShares, const [
          400,
          400,
          400,
          400,
          400,
          400,
        ]);
        expect(result.collectionFeeShares.reduce((a, b) => a + b), 2400);
      },
    );

    test('including self immediately changes suggested collection shares', () {
      AllocationResult allocate(bool includeSelf) => allocateWholeTwd(
        itemAmountsMinor: const [10000, 10000, 10000],
        isSelf: const [true, false, false],
        deliveryFeeMinor: 500,
        serviceFeeMinor: 0,
        discountMinor: 0,
        includeSelfInDeliveryFee: includeSelf,
        includeSelfInServiceFee: false,
        discountEligible: const [false, false, false],
      );

      expect(allocate(false).suggestedDues, const [10000, 10300, 10300]);
      expect(allocate(true).suggestedDues, const [10200, 10200, 10200]);
    });

    test('supports an order without a self participant', () {
      final result = allocateWholeTwd(
        itemAmountsMinor: const [12000, 18000, 18000],
        isSelf: const [false, false, false],
        deliveryFeeMinor: 0,
        serviceFeeMinor: 3000,
        discountMinor: 600,
        includeSelfInDeliveryFee: false,
        includeSelfInServiceFee: false,
        discountEligible: const [true, true, true],
      );

      expect(result.feeShares, const [1000, 1000, 1000]);
      expect(result.collectionFeeShares, const [1000, 1000, 1000]);
      expect(result.discountShares, const [200, 200, 200]);
      expect(result.actualDues, const [12800, 18800, 18800]);
      expect(result.suggestedDues, result.actualDues);
    });

    test('rejects fractional TWD inputs', () {
      expect(
        () => allocateWholeTwd(
          itemAmountsMinor: const [10050, 10000],
          isSelf: const [true, false],
          deliveryFeeMinor: 0,
          serviceFeeMinor: 0,
          discountMinor: 0,
          includeSelfInDeliveryFee: false,
          includeSelfInServiceFee: false,
          discountEligible: const [false, false],
        ),
        throwsFormatException,
      );
    });

    test(
      'fixed discount stays put and automatic participants fill remainder',
      () {
        final result = allocateWholeTwd(
          itemAmountsMinor: const [10000, 10000, 10000],
          isSelf: const [true, false, false],
          deliveryFeeMinor: 0,
          serviceFeeMinor: 0,
          discountMinor: 1000,
          includeSelfInDeliveryFee: false,
          includeSelfInServiceFee: false,
          discountEligible: const [false, true, true],
          fixedDiscountSharesMinor: const [null, 700, null],
        );

        expect(result.discountShares, const [0, 700, 300]);
      },
    );

    test('requires an eligible participant when order has discount', () {
      expect(
        () => allocateDiscountWholeTwd(
          totalMinor: 100,
          discountEligible: const [false, false],
          participantCount: 2,
          fixedSharesMinor: const [null, null],
        ),
        throwsFormatException,
      );
    });

    test('rejects fixed discounts above order discount', () {
      expect(
        () => allocateDiscountWholeTwd(
          totalMinor: 500,
          discountEligible: const [true, true],
          participantCount: 2,
          fixedSharesMinor: const [600, null],
        ),
        throwsFormatException,
      );
    });

    test('redistributes around fixed fee shares with stable remainder', () {
      final result = redistributeFixedSharesWholeTwd(
        totalMinor: 2000,
        fixedSharesMinor: const [0, null, 300, null, null, null],
      );

      expect(result.fixedTotalMinor, 300);
      expect(result.automaticTotalMinor, 1700);
      expect(result.shares, const [0, 500, 300, 400, 400, 400]);
      expect(result.shares.reduce((a, b) => a + b), 2000);
    });

    test('keeps every manual fee unchanged', () {
      final result = redistributeFixedSharesWholeTwd(
        totalMinor: 1200,
        fixedSharesMinor: const [200, null, 500],
      );

      expect(result.shares, const [200, 500, 500]);
    });

    test('rejects fixed fees above the allocation target', () {
      expect(
        () => redistributeFixedSharesWholeTwd(
          totalMinor: 500,
          fixedSharesMinor: const [300, 300, null],
        ),
        throwsFormatException,
      );
    });

    test('requires an automatic participant when a remainder exists', () {
      expect(
        () => redistributeFixedSharesWholeTwd(
          totalMinor: 500,
          fixedSharesMinor: const [200, 200],
        ),
        throwsFormatException,
      );
    });
  });
}
