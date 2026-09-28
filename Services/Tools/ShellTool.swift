//
//  ShellTool.swift
//  iOS Agent Sandbox
//
//  tool "execute_shell" — รันคำสั่งบนเครื่องผ่าน ShellService (posix_spawn)
//  โหมดอนุมัติ (ค่าเริ่มต้น: เปิด) จะเด้งถามผู้ใช้ทุกครั้งก่อนรัน
//
//  Foundation-only → รัน unit test/E2E ได้ทุกแพลตฟอร์ม (ไม่แตะ UIKit)
//

import Foundation

struct ExecuteShellTool: AgentTool {

    let descriptor = ToolDescriptor(name: "execute_shell",
                                    thaiLabel: "รันคำสั่ง shell",
                                    summary: "รันคำสั่ง Unix บนเครื่อง (เช่น ls, cat, df, plutil) แล้วคืน stdout/stderr/exit code",
                                    category: .shell,
                                    alwaysRequiresApproval: true)

    var definition: ToolDefinition {
        ToolDefinition(
            name: descriptor.name,
            description: "รันคำสั่ง shell บนอุปกรณ์ผ่าน /bin/sh แล้วคืนผลลัพธ์ (exit code, stdout, stderr) " +
                "มีเพดานเวลา 30 วินาทีต่อคำสั่ง (ปรับได้ถึง 120) ใช้สำหรับสำรวจเครื่อง ตรวจสิทธิ์ หรือรันยูทิลิตี้ที่มีอยู่จริง " +
                "ห้ามใช้คำสั่งที่ลบข้อมูลโดยไม่บอกผู้ใช้ก่อน เพราะคำสั่งจะถูกถามอนุมัติทุกครั้ง",
            parameters: .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("command", .object([
                        ("type", .string("string")),
                        ("description", .string("คำสั่งที่จะรัน (ส่งผ่าน /bin/sh -c)"))
                    ])),
                    ("timeout_seconds", .object([
                        ("type", .string("integer")),
                        ("description", .string("เวลาสูงสุดเป็นวินาที (ค่าเริ่มต้น 30, สูงสุด 120)"))
                    ])),
                    ("working_directory", .object([
                        ("type", .string("string")),
                        ("description", .string("โฟลเดอร์ที่ใช้เป็นจุดเริ่มต้นของคำสั่ง (ไม่บังคับ)"))
                    ]))
                ])),
                ("required", .array([.string("command")]))
            ])
        )
    }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) async -> ToolExecutionResult {
        let args = ToolArguments(arguments)

        let command: String
        do {
            command = try args.string("command")
        } catch {
            return ToolResults.invalidArguments(error.localizedDescription)
        }

        let timeoutSeconds = args.intInRange("timeout_seconds",
                                             default: Int(NetworkTimeouts.shellSeconds),
                                             min: 1,
                                             max: Int(NetworkTimeouts.maximumShellSeconds))

        var workingDirectory: String?
        if let rawDirectory = args.optionalString("working_directory") {
            workingDirectory = PathGuard.normalize(rawDirectory, workspace: context.workspacePath)
        }

        context.reportProgress("กำลังรันคำสั่ง shell…")

        let assessment = RiskyCommandDetector.assess(shellCommand: command, workspace: context.workspacePath)

        do {
            let result = try await ShellService.shared.run(command: command,
                                                           timeout: TimeInterval(timeoutSeconds),
                                                           workingDirectory: workingDirectory,
                                                           preferRoot: context.runShellAsRoot)

            if result.wasCancelled {
                return .failure(.cancelled, "คำสั่งถูกยกเลิกโดยผู้ใช้")
            }

            var sections: [String] = []
            var header = "คำสั่ง: \(command)\n"
            header += "exit code: \(result.exitCode) • ใช้เวลา \(String(format: "%.2f", result.duration)) วินาที"
            if result.timedOut {
                header += " • หมดเวลา \(timeoutSeconds) วินาที จึงถูกยกเลิก (คำสั่งค้างหรือรอ input)"
            }
            if result.outputTruncated {
                header += " • ข้อมูลที่อ่านได้ถูกตัดที่ 256KB"
            }
            if assessment.level != .normal {
                header += "\nความเสี่ยงที่ตรวจพบ: \(assessment.summaryText)"
            }
            // เฟส 3: บอกให้ชัดว่ารันในนามใคร เพื่อให้ผู้ใช้ (และโมเดล) วางแผนถูก
            header += "\nรันในนาม: \(result.launchMode.thaiName) • shell: \(result.shellPath)"
            if let warning = result.privilegeWarning {
                header += "\n⚠️ \(warning)"
            }
            sections.append(header)

            let stdout = result.stdout.trimmingCharacters(in: .newlines)
            let stderr = result.stderr.trimmingCharacters(in: .newlines)

            if !stdout.isEmpty {
                sections.append("stdout:\n\(stdout)")
            }
            if !stderr.isEmpty {
                sections.append("stderr:\n\(stderr)")
            }
            if stdout.isEmpty && stderr.isEmpty {
                sections.append("(คำสั่งไม่ส่งข้อมูลออกมา)")
            }

            let text = sections.joined(separator: "\n\n")
            if result.timedOut {
                return .failure(.timeout, text)
            }
            if result.exitCode != 0 {
                return .failure(.failed, text)
            }
            return .ok(text)
        } catch let shellError as ShellError {
            return .failure(.failed, shellError.localizedDescription)
        } catch {
            let mapped = ToolErrorMapper.describe(error)
            return .failure(mapped.kind, mapped.message)
        }
    }

    func assessRisk(arguments: [String: JSONValue], workspace: String) -> RiskAssessment {
        let args = ToolArguments(arguments)
        guard let command = args.optionalString("command") else { return .safe }
        return RiskyCommandDetector.assess(shellCommand: command, workspace: workspace)
    }
}
