//
//  ToolRegistry.swift
//  iOS Agent Sandbox
//
//  ทะเบียน tools ที่ Agent ใช้ได้ในเฟส 2 (9 ตัว)
//  ใช้สองทาง: (1) ส่งสคีมาให้โมเดล (2) ค้นหา tool ตามชื่อเพื่อรันจริง
//
//  Foundation-only → รัน unit test/E2E ได้ทุกแพลตฟอร์ม
//

import Foundation

final class ToolRegistry {

    /// tools ทั้งหมดเรียงตามลำดับที่ต้องการให้โมเดลเห็น
    let tools: [AgentTool]

    private let index: [String: AgentTool]

    init(tools: [AgentTool]) {
        self.tools = tools
        var map: [String: AgentTool] = [:]
        for tool in tools {
            map[tool.descriptor.name] = tool
        }
        self.index = map
    }

    /// ทะเบียนมาตรฐาน — เฟส 2 ให้ tools ครบ 9 ตัว และเฟส 6 เพิ่มชุดจัดการ/แก้ไขไฟล์อีก 6 ตัว
    static func makeDefault() -> ToolRegistry {
        ToolRegistry(tools: [
            // อ่านและสำรวจ
            ReadFileTool(),
            ListDirectoryTool(),
            SearchFilesTool(),
            SearchContentTool(),
            // เขียนและแก้ไข
            WriteFileTool(),
            EditFileTool(),
            CreateDirectoryTool(),
            MoveFileTool(),
            CopyFileTool(),
            DeleteFileTool(),
            // ระบบและเครือข่าย
            ExecuteShellTool(),
            HttpRequestTool(),
            DownloadFileTool(),
            WebSearchTool(),
            FetchWebpageTool()
        ])
    }

    /// สคีมาที่ส่งไปกับคำขอ (เรียงตามลำดับในทะเบียน)
    var definitions: [ToolDefinition] {
        tools.map { $0.definition }
    }

    /// หา tool จากชื่อที่โมเดลเรียก
    func tool(named name: String) -> AgentTool? {
        index[name]
    }

    var toolNames: [String] {
        tools.map { $0.descriptor.name }
    }

    /// รายการสำหรับแสดงในหน้า Settings (ชื่อไทย + คำอธิบาย)
    var inventoryText: String {
        tools.map { tool in
            "• \(tool.descriptor.name) (\(tool.descriptor.thaiLabel)) — \(tool.descriptor.summary)"
        }.joined(separator: "\n")
    }
}
