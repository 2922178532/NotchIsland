import XCTest
@testable import NotchIsland

/// `PowerMetricsParser` 是纯函数，直接构造 powermetrics 的 plist 输出来验证。
final class PowerMetricsParserTests: XCTestCase {

    // MARK: - 构造测试用的 plist

    private func plist(_ root: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    private func taskDict(
        pid: Int,
        name: String,
        energyImpactPerS: Double? = nil,
        energyImpact: Double? = nil,
        cpuMsPerS: Double? = nil,
        gpuMsPerS: Double? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = ["pid": pid, "name": name]
        if let energyImpactPerS { dict["energy_impact_per_s"] = energyImpactPerS }
        if let energyImpact { dict["energy_impact"] = energyImpact }
        if let cpuMsPerS { dict["cputime_ms_per_s"] = cpuMsPerS }
        if let gpuMsPerS { dict["gputime_ms_per_s"] = gpuMsPerS }
        return dict
    }

    // MARK: - tasks(from:)

    /// 新版 macOS 的形态：coalitions 数组里带 tasks 子数组。
    func testParsesNestedCoalitionTasks() {
        let data = plist([
            "coalitions": [
                ["name": "com.apple.Safari", "tasks": [
                    taskDict(pid: 501, name: "Safari", energyImpactPerS: 120.5, cpuMsPerS: 42, gpuMsPerS: 3),
                    taskDict(pid: 502, name: "Safari Helper", energyImpactPerS: 10),
                ]],
                ["name": "com.example.other", "tasks": [
                    taskDict(pid: 601, name: "Other", energyImpactPerS: 5),
                ]],
            ],
        ])

        let tasks = PowerMetricsParser.tasks(from: data)

        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0], PMTask(
            pid: 501, name: "Safari", energyImpact: 120.5, cpuMsPerS: 42, gpuMsPerS: 3
        ))
        // 缺失的字段落到 0，而不是丢掉整条记录。
        XCTAssertEqual(tasks[1], PMTask(
            pid: 502, name: "Safari Helper", energyImpact: 10, cpuMsPerS: 0, gpuMsPerS: 0
        ))
        XCTAssertEqual(tasks[2].name, "Other")
    }

    /// 旧版形态：顶层直接是平铺的 tasks 数组。
    func testParsesFlatTasks() {
        let data = plist([
            "tasks": [
                taskDict(pid: 300, name: "kernel_task", energyImpactPerS: 8, cpuMsPerS: 100),
            ],
        ])

        let tasks = PowerMetricsParser.tasks(from: data)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].pid, 300)
        XCTAssertEqual(tasks[0].cpuMsPerS, 100)
    }

    /// coalition 自身就是一条任务（没有 tasks 子数组）时也要收进来。
    func testParsesCoalitionWithoutNestedTasks() {
        let data = plist([
            "coalitions": [
                taskDict(pid: 700, name: "Standalone", energyImpactPerS: 33),
            ],
        ])

        let tasks = PowerMetricsParser.tasks(from: data)

        XCTAssertEqual(tasks.map(\.name), ["Standalone"])
        XCTAssertEqual(tasks[0].energyImpact, 33)
    }

    /// ALL_TASKS 聚合项的 pid 是 -2，必须排除，否则总量会被算两遍。
    func testExcludesNegativePIDAggregate() {
        let data = plist([
            "tasks": [
                taskDict(pid: -2, name: "ALL_TASKS", energyImpactPerS: 999),
                taskDict(pid: 0, name: "kernel", energyImpactPerS: 1),
                taskDict(pid: 42, name: "App", energyImpactPerS: 2),
            ],
        ])

        let tasks = PowerMetricsParser.tasks(from: data)

        XCTAssertEqual(tasks.map(\.name), ["kernel", "App"], "pid -2 应被排除，pid 0 应保留")
    }

    /// 没有 energy_impact_per_s 时退回 energy_impact。
    func testFallsBackToEnergyImpactField() {
        let data = plist([
            "tasks": [taskDict(pid: 10, name: "Legacy", energyImpact: 77)],
        ])

        XCTAssertEqual(PowerMetricsParser.tasks(from: data).first?.energyImpact, 77)
    }

    /// per_s 与非 per_s 同时存在时，优先取 per_s。
    func testPrefersPerSecondEnergyField() {
        let data = plist([
            "tasks": [taskDict(pid: 10, name: "Both", energyImpactPerS: 5, energyImpact: 500)],
        ])

        XCTAssertEqual(PowerMetricsParser.tasks(from: data).first?.energyImpact, 5)
    }

    /// 缺 name 或 pid 的记录直接跳过，不影响同批次里其他记录。
    func testSkipsMalformedEntries() {
        let data = plist([
            "tasks": [
                ["pid": 1],                       // 缺 name
                ["name": "NoPID"],                // 缺 pid
                taskDict(pid: 2, name: "Good"),
            ],
        ])

        XCTAssertEqual(PowerMetricsParser.tasks(from: data).map(\.name), ["Good"])
    }

    func testReturnsEmptyForGarbageInput() {
        XCTAssertTrue(PowerMetricsParser.tasks(from: Data("not a plist".utf8)).isEmpty)
        XCTAssertTrue(PowerMetricsParser.tasks(from: Data()).isEmpty)
    }

    /// 顶层是数组而不是字典时不应崩溃。
    func testReturnsEmptyForNonDictionaryRoot() {
        let data = try! PropertyListSerialization.data(
            fromPropertyList: ["a", "b"], format: .xml, options: 0
        )
        XCTAssertTrue(PowerMetricsParser.tasks(from: data).isEmpty)
    }

    /// 两种形态同时出现时应合并，而不是只取一种。
    func testMergesCoalitionsAndFlatTasks() {
        let data = plist([
            "coalitions": [["tasks": [taskDict(pid: 1, name: "FromCoalition")]]],
            "tasks": [taskDict(pid: 2, name: "FromFlat")],
        ])

        XCTAssertEqual(
            PowerMetricsParser.tasks(from: data).map(\.name),
            ["FromCoalition", "FromFlat"]
        )
    }

    // MARK: - splitStream(buffer:)

    /// powermetrics 用 NUL 字节分隔样本，完整的文档要被切出来。
    func testSplitStreamExtractsCompleteDocuments() {
        var buffer = Data("first\0second\0".utf8)

        let documents = PowerMetricsParser.splitStream(buffer: &buffer)

        XCTAssertEqual(documents.map { String(decoding: $0, as: UTF8.self) }, ["first", "second"])
        XCTAssertTrue(buffer.isEmpty, "全部消费完后缓冲区应为空")
    }

    /// 末尾没有 NUL 的残片必须留在缓冲区里等下一次读取，否则会丢样本。
    func testSplitStreamKeepsTrailingRemainder() {
        var buffer = Data("complete\0partia".utf8)

        let documents = PowerMetricsParser.splitStream(buffer: &buffer)

        XCTAssertEqual(documents.map { String(decoding: $0, as: UTF8.self) }, ["complete"])
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "partia")
    }

    /// 上一次的残片与新数据拼起来后应还原成完整文档。
    func testSplitStreamResumesAcrossCalls() {
        var buffer = Data("par".utf8)
        XCTAssertTrue(PowerMetricsParser.splitStream(buffer: &buffer).isEmpty)

        buffer.append(Data("tial\0".utf8))
        let documents = PowerMetricsParser.splitStream(buffer: &buffer)

        XCTAssertEqual(documents.map { String(decoding: $0, as: UTF8.self) }, ["partial"])
        XCTAssertTrue(buffer.isEmpty)
    }

    /// 连续的 NUL 会产生空片段，应跳过而不是塞一堆空 Data 进去。
    func testSplitStreamSkipsEmptyChunks() {
        var buffer = Data("a\0\0\0b\0".utf8)

        let documents = PowerMetricsParser.splitStream(buffer: &buffer)

        XCTAssertEqual(documents.map { String(decoding: $0, as: UTF8.self) }, ["a", "b"])
    }

    func testSplitStreamOnEmptyBuffer() {
        var buffer = Data()
        XCTAssertTrue(PowerMetricsParser.splitStream(buffer: &buffer).isEmpty)
        XCTAssertTrue(buffer.isEmpty)
    }

    /// 切出来的片段要能被 tasks(from:) 直接解析，两个函数串起来跑一遍。
    func testSplitStreamProducesParsableDocuments() {
        var buffer = plist(["tasks": [taskDict(pid: 1, name: "A", energyImpactPerS: 1)]])
        buffer.append(0)
        buffer.append(plist(["tasks": [taskDict(pid: 2, name: "B", energyImpactPerS: 2)]]))
        buffer.append(0)

        let documents = PowerMetricsParser.splitStream(buffer: &buffer)

        XCTAssertEqual(documents.count, 2)
        XCTAssertEqual(documents.flatMap { PowerMetricsParser.tasks(from: $0) }.map(\.name), ["A", "B"])
    }
}
