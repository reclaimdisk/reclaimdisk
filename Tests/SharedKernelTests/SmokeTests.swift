import Testing
@testable import SharedKernel

@Test func moduleLinks() {
    #expect(SharedKernelContext.self == SharedKernelContext.self)
}
