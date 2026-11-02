import Foundation
import Testing
@testable import JGModel

struct DuplicatePlanTests {
    private func asset(_ id: Int64, size: Int64 = 10, age: TimeInterval) -> Asset {
        Asset(
            id: id, folderID: 1, name: "\(id).jpg", url: URL(fileURLWithPath: "/lib/\(id).jpg"), kind: .photo,
            typeIdentifier: nil, size: size, modifiedAt: Date(timeIntervalSince1970: 1000 + age), createdAt: nil,
            width: nil, height: nil, orientation: nil, duration: nil, frameRate: nil, codec: nil, capturedAt: nil,
            state: .present, metadataState: .extracted
        )
    }

    @Test func biggestGroupsFirstAndTheOldestStays() {
        let plan = DuplicatePlan(groups: [
            [asset(1, age: 5), asset(2, age: 1)],
            [asset(3, age: 9), asset(4, age: 3), asset(5, age: 7)],
        ])
        #expect(plan.groups.map { $0.copies.map(\.id) } == [[4, 5, 3], [2, 1]])
        #expect(plan.ticked == [5, 3, 1])
        #expect(plan.extraCopies == 3)
        #expect(plan.tickedBytes == 30)
    }

    @Test func oneCopyPerGroupCanNeverBeTicked() {
        var plan = DuplicatePlan(groups: [[asset(1, age: 1), asset(2, age: 2)]])
        let keptOldest = plan.toggle(1)
        #expect(!keptOldest)
        #expect(plan.ticked == [2])
        let untick = plan.toggle(2)
        let tickOther = plan.toggle(1)
        #expect(untick && tickOther)
        #expect(plan.ticked == [1])
        let tickBoth = plan.toggle(2)
        #expect(!tickBoth)
        // The copy that stays is the unticked one.
        #expect(plan.removals.map { [$0.copy.id, $0.kept.id] } == [[1, 2]])
    }
}
