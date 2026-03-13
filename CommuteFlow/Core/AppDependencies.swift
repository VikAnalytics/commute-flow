import Foundation

protocol AppDependencies {
    var transitService: TransitProviding { get }
}

struct LiveAppDependencies: AppDependencies {
    let transitService: TransitProviding

    init(transitService: TransitProviding = TransitService()) {
        self.transitService = transitService
    }
}
