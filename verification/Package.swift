// swift-tools-version:5.9
//
//  Package.swift — แพ็กเกจสำหรับ "รันทดสอบแกนกลางของเฟส 1" นอก Xcode
//
//  เป้าหมาย: พิสูจน์ว่า logic ที่เสี่ยงที่สุดของแอป (การรวม tool_calls delta ที่ถูกแบ่งเป็น chunk,
//  การซ่อม JSON ที่ถูกตัดกลางทาง, การถอดรหัส SSE, retry policy, การเข้ารหัส payload)
//  ทำงานถูกต้องจริง โดยใช้ "ไฟล์ต้นฉบับของโปรเจกต์" ไม่ใช่โค้ดที่เขียนใหม่
//
//  ใช้งาน:  bash verification/run-verification.sh
//           (สคริปต์จะคัดลอกไฟล์ต้นฉบับ 4 ไฟล์เข้ามา + ตรวจ sha256 ว่าตรงกัน แล้วรัน swift test)
//
import PackageDescription

let package = Package(
    name: "OpenRouterCoreVerification",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .target(
            name: "OpenRouterCore",
            path: "Sources/OpenRouterCore"
        ),
        .testTarget(
            name: "OpenRouterCoreTests",
            dependencies: ["OpenRouterCore"],
            path: "Tests/OpenRouterCoreTests"
        )
    ]
)
