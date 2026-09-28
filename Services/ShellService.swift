//
//  ShellService.swift
//  iOS Agent Sandbox
//
//  รันคำสั่ง shell บน iOS ด้วย posix_spawn เท่านั้น
//  (Process/NSTask ใช้บน iOS ไม่ได้ — Foundation ไม่มีให้ในระบบปฏิบัติการนี้)
//
//  คุณสมบัติ:
//  - หา shell ที่มีจริงบนเครื่อง: /var/jb/bin/sh (rootless jailbreak) → /bin/sh
//  - อ่าน stdout และ stderr ผ่าน pipe แยกกัน (ไม่ตายเมื่อ pipe เต็ม)
//  - หมดเวลาแล้ว kill ให้อัตโนมัติ (SIGKILL) และรายงานว่าหมดเวลา
//  - ยกเลิกได้ทันทีเมื่อผู้ใช้กดหยุด (withTaskCancellationHandler → kill)
//  - จำกัดปริมาณที่เก็บเข้าหน่วยความจำ (RAM 2GB): เก็บสูงสุด 256KB ต่อ stream
//
//  เฟส 3 — รันเป็น root ผ่าน persona ของ TrollStore:
//  - posix_spawnattr_set_persona_np / _uid_np / _gid_np ถูกเรียกผ่าน dlsym
//    (ไม่ผูกกับ header ของ SDK จึงคอมไพล์ได้ทุกเวอร์ชันและถอยกลับได้ปลอดภัย)
//  - ถ้าสลับ persona ไม่สำเร็จ → ลองใหม่แบบผู้ใช้ปัจจุบัน แล้วรายงานเหตุผลจริงให้ผู้ใช้เห็น
//  - ผลลัพธ์ของทุกคำสั่งบอกเสมอว่า "รันในนามใคร" (uid เท่าไร ผ่านกลไกไหน)
//
//  Foundation + Darwin POSIX เท่านั้น → ไม่แตะ UIKit
//

import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - ผลลัพธ์คำสั่ง

struct ShellResult: Equatable {
    /// โค้ดจบงานของโปรเซส (0 = สำเร็จ)
    let exitCode: Int32
    let stdout: String
    let stderr: String
    /// true = ถูกฆ่าเพราะเกินเวลาที่กำหนด
    let timedOut: Bool
    /// true = ผู้ใช้กดหยุดระหว่างทำงาน
    let wasCancelled: Bool
    /// เวลาที่ใช้จริง
    let duration: TimeInterval
    /// จำนวนไบต์ที่อ่านได้ (ก่อนตัดความยาวเพื่อแสดงผล)
    let stdoutBytes: Int
    let stderrBytes: Int
    /// true = ข้อมูลถูกตัดเพราะเกินปริมาณที่เก็บได้
    let outputTruncated: Bool

    // MARK: ข้อมูลการรัน (เฟส 3)
    /// shell ที่ใช้จริง
    let shellPath: String
    /// รันในนามผู้ใช้ปัจจุบันหรือ root (persona)
    let launchMode: ShellLaunchMode
    /// เหตุผลที่เลือกโหมดนี้ (ภาษาไทย)
    let launchReason: String
    /// ข้อความเตือนเมื่อลอง root แล้วไม่สำเร็จ (nil = ไม่มีปัญหา)
    let privilegeWarning: String?
}

// MARK: - ข้อผิดพลาดของ shell

enum ShellError: LocalizedError {
    case shellNotFound([String])
    case spawnFailed(reason: String, code: Int32)
    case emptyCommand

    var errorDescription: String? {
        switch self {
        case .shellNotFound(let attempted):
            return "ไม่พบ shell บนเครื่องนี้ (ลองแล้ว: \(attempted.joined(separator: ", "))) — " +
                "ถ้าเครื่องยังไม่เจลเบรค/ติดตั้ง TrollStore แอปจะไม่สามารถรันคำสั่งได้"
        case .spawnFailed(let reason, let code):
            return "เริ่มโปรเซสไม่สำเร็จ (\(reason), errno \(code))"
        case .emptyCommand:
            return "คำสั่งว่างเปล่า"
        }
    }
}

// MARK: - บริการรันคำสั่ง

final class ShellService: @unchecked Sendable {

    static let shared = ShellService()

    /// shell ที่จะลองตามลำดับ — ตัวแรกที่มีจริงจะถูกใช้ (นิยามอยู่ใน PrivilegePolicy)
    static var candidateShellPaths: [String] { PrivilegePolicy.shellSearchPaths }

    /// เก็บข้อมูลได้สูงสุดต่อหนึ่ง stream (ไบต์) — ที่เหลืออ่านทิ้ง
    private static let captureLimit = 256 * 1024

    private let lock = NSLock()
    private var currentPid: pid_t?
    /// ผู้ใช้กดหยุดระหว่างที่คำสั่งกำลังทำงาน (ใช้แทน Task.isCancelled ซึ่งไม่ทำงานในคิว Dispatch)
    private var cancellationRequested = false

    private init() { }

    /// อ่าน/ตั้งธงการยกเลิกอย่างปลอดภัยระหว่างเธรด
    private var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    private func markCancellationRequested() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    private func resetCancellationFlag() {
        lock.lock()
        cancellationRequested = false
        lock.unlock()
    }

    // MARK: หา shell

    /// shell ที่มีอยู่จริงบนเครื่องนี้ (nil = ไม่มีเลย)
    func resolveShellPath() -> String? {
        let fileManager = FileManager.default
        for path in ShellService.candidateShellPaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    /// shell ที่จะใช้จริง (คืน path ตัวแรกของรายการเมื่อหาไม่เจอ เพื่อให้ข้อความ error บอกได้ว่าลองอะไรไปแล้ว)
    var shellPathForDisplay: String {
        resolveShellPath() ?? ShellService.candidateShellPaths[0]
    }

    // MARK: รันคำสั่ง

    /// รันคำสั่งแบบ async พร้อม timeout และการยกเลิก
    func run(command: String,
             timeout: TimeInterval = NetworkTimeouts.shellSeconds,
             workingDirectory: String? = nil,
             preferRoot: Bool = false) async throws -> ShellResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShellError.emptyCommand }
        guard let shellPath = resolveShellPath() else { throw ShellError.shellNotFound(PrivilegePolicy.shellSearchPaths) }

        let effective = min(max(timeout, 1), NetworkTimeouts.maximumShellSeconds)
        let finalCommand = ShellService.commandWithWorkingDirectory(trimmed, directory: workingDirectory)

        // ตัดสินใจว่าจะพยายามรันเป็น root หรือไม่ (เหตุผลอยู่ใน PrivilegePolicy เพื่อให้ทดสอบได้)
        let decision = PrivilegePolicy.decideLaunchMode(preferRoot: preferRoot,
                                                       canUsePersona: ShellService.personaSymbolsAvailable,
                                                       currentUserID: ShellService.currentUserID)

        resetCancellationFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try self.runBlocking(shellPath: shellPath,
                                                          command: finalCommand,
                                                          timeout: effective,
                                                          decision: decision)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.terminateCurrentProcess()
        }
    }

    /// ขอยกเลิกคำสั่งที่กำลังทำงานอยู่ (เรียกเมื่อผู้ใช้กดหยุด)
    /// ตั้งธงไว้ก่อนเสมอ เพื่อให้กรณีกดหยุดก่อนโปรเซสเกิด ยังถูกจับได้ตอน spawn
    func terminateCurrentProcess() {
        lock.lock()
        cancellationRequested = true
        let pid = currentPid
        lock.unlock()
        guard let pid = pid, pid > 0 else { return }
        kill(pid, SIGKILL)
    }

    // MARK: - การทำงานจริง (บล็อก)

    private func runBlocking(shellPath: String,
                             command: String,
                             timeout: TimeInterval,
                             decision: LaunchModeDecision) throws -> ShellResult {
        var stdoutPipe: [Int32] = [0, 0]
        var stderrPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0 else {
            throw ShellError.spawnFailed(reason: "สร้าง pipe ของ stdout ไม่สำเร็จ", code: errno)
        }
        guard pipe(&stderrPipe) == 0 else {
            close(stdoutPipe[0]); close(stdoutPipe[1])
            throw ShellError.spawnFailed(reason: "สร้าง pipe ของ stderr ไม่สำเร็จ", code: errno)
        }

        // บน Darwin posix_spawn_file_actions_t เป็น opaque pointer (ต้องประกาศเป็น Optional แล้วให้ init สร้างให้)
        // บน Linux/glibc เป็น struct ที่สร้างด้วย () ได้ — เขียนให้ถูกทั้งสองแบบ
        #if canImport(Darwin)
        var fileActions: posix_spawn_file_actions_t?
        #else
        var fileActions = posix_spawn_file_actions_t()
        #endif
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[1])
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[1])

        let argv = ["/bin/sh", "-c", command]
        let runAsRoot: Bool
        if case .rootPersona = decision.mode {
            runAsRoot = true
        } else {
            runAsRoot = false
        }
        let environment = PrivilegePolicy.environment(uid: runAsRoot ? 0 : ShellService.currentUserID,
                                                      temporaryDirectory: NSTemporaryDirectory())

        var pid: pid_t = 0
        var argvPointers: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        argvPointers.append(nil)
        var envPointers: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
        envPointers.append(nil)

        var launchMode = decision.mode
        var privilegeWarning: String?

        // ชนิดของ posix_spawnattr_t ต่างกันคนละแบบ:
        //   Darwin → opaque pointer (ต้องประกาศเป็น Optional แล้วให้ init สร้างให้)
        //   Linux  → struct ของ glibc ที่สร้างด้วย () ได้
        // เขียนแบบมีเงื่อนไขไว้ที่เดียว แล้วใช้ต่อได้เหมือนกันทั้งสองฝั่ง
        #if canImport(Darwin)
        var attributes: posix_spawnattr_t?
        #else
        var attributes = posix_spawnattr_t()
        #endif

        #if canImport(Darwin)
        var attributesInitialized = posix_spawnattr_init(&attributes) == 0
        #else
        _ = posix_spawnattr_init(&attributes)
        let attributesInitialized = true
        #endif

        if runAsRoot {
            ShellService.configurePersonaAttributes(&attributes)
        }

        /// เรียก posix_spawn หนึ่งครั้งด้วย attributes ปัจจุบัน
        func spawnProcess() -> Int32 {
            argvPointers.withUnsafeBufferPointer { argvBuffer -> Int32 in
                envPointers.withUnsafeBufferPointer { envBuffer -> Int32 in
                    // baseAddress เป็น nil ได้ในทางทฤษฎีเท่านั้น (อาเรย์มี nil ต่อท้ายเสมอ)
                    // แต่ตรวจไว้ก่อนเพื่อไม่ต้องใช้ force unwrap
                    guard let argvBase = argvBuffer.baseAddress, let envBase = envBuffer.baseAddress else {
                        return Int32(EINVAL)
                    }
                    return posix_spawn(&pid, shellPath, &fileActions, &attributes, argvBase, envBase)
                }
            }
        }

        /// ทิ้ง attributes เดิม แล้วสร้างใหม่แบบไม่ตั้ง persona (ใช้ตอนถอยกลับ)
        func resetAttributesWithoutPersona() {
            #if canImport(Darwin)
            if attributesInitialized {
                posix_spawnattr_destroy(&attributes)
            }
            attributesInitialized = posix_spawnattr_init(&attributes) == 0
            #else
            attributes = posix_spawnattr_t()
            #endif
            _ = attributesInitialized
        }

        var spawnStatus = spawnProcess()

        // มีคนกดหยุดระหว่างเตรียมคำสั่ง → ฆ่าทันทีที่โปรเซสเกิด (กันโปรเซสค้าง)
        if isCancellationRequested, spawnStatus == 0, pid > 0 {
            kill(pid, SIGKILL)
        }

        if spawnStatus != 0, runAsRoot {
            // สลับ persona ไม่สำเร็จ → ถอยกลับไปรันแบบผู้ใช้ปัจจุบัน และบอกผู้ใช้ตามจริง
            let failureDetail = String(cString: strerror(spawnStatus))
            resetAttributesWithoutPersona()
            let fallbackStatus = spawnProcess()
            if fallbackStatus == 0 {
                launchMode = .currentUser
                privilegeWarning = "รันในนาม root ไม่สำเร็จ (\(failureDetail), errno \(spawnStatus)) — " +
                    "รันในนามผู้ใช้ปัจจุบันแทน คำสั่งที่ต้องเป็น root อาจทำไม่ได้"
                spawnStatus = 0
            } else {
                spawnStatus = fallbackStatus
            }
        }

        for pointer in argvPointers where pointer != nil {
            free(pointer)
        }
        for pointer in envPointers where pointer != nil {
            free(pointer)
        }

        #if canImport(Darwin)
        if attributesInitialized {
            posix_spawnattr_destroy(&attributes)
        }
        #endif
        posix_spawn_file_actions_destroy(&fileActions)

        // ปิดฝั่งเขียนในโปรเซสแม่ ไม่งั้น read() จะไม่มีวันได้ EOF
        close(stdoutPipe[1])
        close(stderrPipe[1])

        guard spawnStatus == 0 else {
            close(stdoutPipe[0]); close(stderrPipe[0])
            throw ShellError.spawnFailed(reason: String(cString: strerror(spawnStatus)), code: spawnStatus)
        }

        lock.lock()
        currentPid = pid
        lock.unlock()

        let startedAt = Date()
        let group = DispatchGroup()
        let collector = OutputCollector(limit: ShellService.captureLimit)
        let stdoutReadFD = stdoutPipe[0]
        let stderrReadFD = stderrPipe[0]

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.collect(from: stdoutReadFD, isStdout: true)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.collect(from: stderrReadFD, isStdout: false)
            group.leave()
        }

        // รอโปรเซสจบแบบมีเพดานเวลา (ตรวจทุก 50 มิลลิวินาที)
        var status: Int32 = 0
        var timedOut = false
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let waitResult = waitpid(pid, &status, WNOHANG)
            if waitResult == pid {
                break
            }
            if waitResult < 0 {
                break // โปรเซสหายไปแล้ว (ถูกเก็บไปที่อื่น) — ออกเพื่อไม่วนไม่จบ
            }
            if Date() >= deadline {
                timedOut = true
                kill(pid, SIGKILL)
                var finalStatus: Int32 = 0
                waitpid(pid, &finalStatus, 0)
                status = finalStatus
                break
            }
            // ตรวจว่าถูกยกเลิกหรือยัง (cancel → handler ข้างนอกตั้งธงและฆ่าโปรเซสให้แล้ว)
            if isCancellationRequested {
                kill(pid, SIGKILL)
                var finalStatus: Int32 = 0
                waitpid(pid, &finalStatus, 0)
                status = finalStatus
                break
            }
            usleep(50_000)
        }

        // รอให้ตัวอ่าน pipe เก็บข้อมูลจนจบ (fd ถูกปิดเพราะโปรเซสลูกจบแล้ว)
        _ = group.wait(timeout: .now() + 3)

        lock.lock()
        currentPid = nil
        lock.unlock()

        let duration = Date().timeIntervalSince(startedAt)
        let wasCancelled = isCancellationRequested
        let exitCode = ShellService.exitCode(fromStatus: status)
        let snapshot = collector.snapshot()

        close(stdoutPipe[0])
        close(stderrPipe[0])

        return ShellResult(exitCode: exitCode,
                           stdout: snapshot.stdout,
                           stderr: snapshot.stderr,
                           timedOut: timedOut,
                           wasCancelled: wasCancelled,
                           duration: duration,
                           stdoutBytes: snapshot.stdoutBytes,
                           stderrBytes: snapshot.stderrBytes,
                           outputTruncated: snapshot.truncated,
                           shellPath: shellPath,
                           launchMode: launchMode,
                           launchReason: decision.reason,
                           privilegeWarning: privilegeWarning)
    }

    // MARK: - ตัวช่วย

    /// uid ของโปรเซสนี้ (501 = mobile, 0 = root)
    static var currentUserID: Int32 {
        Int32(getuid())
    }

    /// ตรวจว่ามีฟังก์ชัน persona ของ XNU อยู่ในระบบหรือไม่
    /// (เรียกผ่าน dlsym เพื่อไม่ต้องพึ่ง header ของ SDK — ถ้าไม่มีก็แค่ไม่ใช้ความสามารถนี้)
    static let personaSymbolsAvailable: Bool = {
        #if canImport(Darwin)
        let names = ["posix_spawnattr_set_persona_np", "posix_spawnattr_set_persona_uid_np", "posix_spawnattr_set_persona_gid_np"]
        for name in names where dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) == nil {
            // -2 = RTLD_DEFAULT (ค้นในโปรเซสเองทั้งหมด)
            return false
        }
        return true
        #else
        // บน Linux/macOS ที่รัน unit test ไม่มี XNU persona — ใช้เส้นทางผู้ใช้ปัจจุบันเท่านั้น
        return false
        #endif
    }()

    #if canImport(Darwin)
    /// ตั้งค่า persona/uid/gid (รันเป็น root ผ่าน TrollStore) ให้ attributes — เรียกผ่าน dlsym
    /// จึงคอมไพล์ได้ทุกเวอร์ชันของ SDK และถอยกลับได้ปลอดภัยถ้าเครื่องไม่มีฟังก์ชันนี้
    static func configurePersonaAttributes(_ pointer: UnsafeMutablePointer<posix_spawnattr_t?>) {
        // ตั้งสัญญาณเริ่มต้นของโปรเซสลูกให้เป็นค่ามาตรฐาน
        posix_spawnattr_setflags(pointer, Int16(POSIX_SPAWN_SETSIGDEF))

        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "posix_spawnattr_set_persona_np") else {
            return
        }
        typealias SetPersonaFunction = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, UInt32, UInt32) -> Int32
        let setPersona = unsafeBitCast(symbol, to: SetPersonaFunction.self)
        _ = setPersona(pointer, PrivilegePolicy.rootPersonaID, PrivilegePolicy.personaFlagsOverride)

        typealias SetIdentifierFunction = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, UInt32) -> Int32

        if let uidSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "posix_spawnattr_set_persona_uid_np") {
            let setUserID = unsafeBitCast(uidSymbol, to: SetIdentifierFunction.self)
            _ = setUserID(pointer, 0)   // uid 0 = root
        }
        if let gidSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "posix_spawnattr_set_persona_gid_np") {
            let setGroupID = unsafeBitCast(gidSymbol, to: SetIdentifierFunction.self)
            _ = setGroupID(pointer, 0)  // gid 0 = root
        }
    }
    #else
    /// บน Linux/macOS ที่รัน unit test ไม่มี persona ของ XNU — ไม่มีอะไรต้องตั้ง
    /// (ฟังก์ชันนี้มีไว้ให้โค้ดที่เรียกใช้คอมไพล์ผ่านทั้งสองแพลตฟอร์ม)
    static func configurePersonaAttributes(_ pointer: UnsafeMutablePointer<posix_spawnattr_t>) {
        _ = pointer
    }
    #endif

    /// แปลง wait status เป็น exit code แบบที่คนทั่วไปเข้าใจ
    static func exitCode(fromStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        if signal == 0 {
            return (status >> 8) & 0xff
        }
        // ถูกฆ่าด้วยสัญญาณ → รายงานเป็น 128 + เลขสัญญาณ (แบบเดียวกับ shell มาตรฐาน)
        return 128 + signal
    }

    /// ใส่ "cd <dir> &&" ข้างหน้าคำสั่งเมื่อผู้ใช้ระบุโฟลเดอร์ทำงาน
    /// (ทำแบบนี้แทน posix_spawn_file_actions_addchdir_np เพื่อให้ใช้ได้ทุกเวอร์ชัน iOS)
    static func commandWithWorkingDirectory(_ command: String, directory: String?) -> String {
        guard let directory = directory?.trimmingCharacters(in: .whitespacesAndNewlines), !directory.isEmpty else {
            return command
        }
        let quoted = "'" + directory.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "cd \(quoted) && \(command)"
    }

}

// MARK: - ตัวเก็บข้อมูลจาก pipe

/// อ่านจาก file descriptor ทีละก้อน (ไม่โหลดทั้งหมดเข้าหน่วยความจำ) และตัดที่เพดานที่กำหนด
private final class OutputCollector {

    private let limit: Int
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutCounter = 0
    private var stderrCounter = 0
    private var didTruncate = false

    init(limit: Int) {
        self.limit = limit
    }

    func collect(from fileDescriptor: Int32, isStdout: Bool) {
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = read(fileDescriptor, &buffer, buffer.count)
            if count > 0 {
                let chunk = Data(buffer[0..<count])
                lock.lock()
                if isStdout {
                    stdoutCounter += count
                    if stdoutData.count < limit {
                        let remaining = limit - stdoutData.count
                        stdoutData.append(chunk.prefix(remaining))
                    } else {
                        didTruncate = true
                    }
                } else {
                    stderrCounter += count
                    if stderrData.count < limit {
                        let remaining = limit - stderrData.count
                        stderrData.append(chunk.prefix(remaining))
                    } else {
                        didTruncate = true
                    }
                }
                lock.unlock()
            } else if count == 0 {
                break
            } else {
                if errno == EINTR { continue }
                break
            }
        }
    }

    func snapshot() -> (stdout: String, stderr: String, stdoutBytes: Int, stderrBytes: Int, truncated: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (Self.decode(stdoutData),
                Self.decode(stderrData),
                stdoutCounter,
                stderrCounter,
                didTruncate)
    }

    /// ถอดรหัสแบบทนทาน: UTF-8 ก่อน แล้วถ้าพังให้ลอง CP1252 (ครอบคลุมข้อความตะวันตก) สุดท้ายใช้ lossy
    private static func decode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        if let text = String(data: data, encoding: .utf8) { return text }
        // UTF-8 อาจพังเพราะถูกตัดกลางตัวอักษร — ตัดท้ายทีละไบต์แล้วลองใหม่ (ไม่เกิน 3 ไบต์)
        if data.count > 4 {
            for drop in 1...3 {
                let cut = data.dropLast(drop)
                if let text = String(data: Data(cut), encoding: .utf8) {
                    return text
                }
            }
        }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}
