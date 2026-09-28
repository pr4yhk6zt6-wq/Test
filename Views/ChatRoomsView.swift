//
//  ChatRoomsView.swift
//  iOS Agent Sandbox
//
//  หน้าจัดการหลายห้องสนทนา (เฟส 5): สร้าง • เปลี่ยนชื่อ • ลบ (ปัดซ้าย) • ค้นหา • เลือกห้อง
//  ใช้ SwiftUI ของ iOS 15 เท่านั้น (ไม่ใช้ NavigationStack)
//

#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

struct ChatRoomsView: View {

    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.presentationMode) private var presentationMode

    @State private var searchText: String = ""
    @State private var showCreateSheet = false
    @State private var newRoomName: String = ""
    @State private var renameTarget: ChatRoom?
    @State private var renameText: String = ""
    @State private var deleteTarget: ChatRoom?

    private var filteredRooms: [ChatRoom] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.rooms }
        return viewModel.rooms.filter { room in
            room.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || room.preview.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchField

                if filteredRooms.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredRooms) { room in
                            row(for: room)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("ห้องสนทนา")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ปิด") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newRoomName = ""
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("สร้างห้องใหม่")
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                nameSheet(title: "สร้างห้องใหม่",
                          placeholder: "ชื่อห้อง เช่น งานบ้าน",
                          text: $newRoomName,
                          confirmTitle: "สร้าง",
                          onConfirm: { name in
                            viewModel.createRoom(named: name)
                            showCreateSheet = false
                          },
                          onCancel: { showCreateSheet = false })
            }
            .sheet(item: $renameTarget) { room in
                nameSheet(title: "เปลี่ยนชื่อห้อง",
                          placeholder: room.name,
                          text: $renameText,
                          confirmTitle: "บันทึก",
                          onConfirm: { name in
                            viewModel.renameRoom(room, to: name)
                            renameTarget = nil
                          },
                          onCancel: { renameTarget = nil })
            }
            .alert(item: $deleteTarget) { room in
                Alert(title: Text("ลบห้อง “\(room.name)”?"),
                      message: Text("ข้อความทั้งหมดในห้องนี้จะถูกลบถาวร"),
                      primaryButton: .destructive(Text("ลบ")) {
                        viewModel.deleteRoom(room)
                      },
                      secondaryButton: .cancel(Text("ยกเลิก")))
            }
        }
        .navigationViewStyle(.stack)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("ค้นหาชื่อห้องหรือข้อความ", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ล้างคำค้นหา")
            }
        }
        .padding(10)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "ยังไม่มีห้องสนทนา" : "ไม่พบห้องที่ตรงกับคำค้นหา")
                .foregroundColor(.secondary)
            if searchText.isEmpty {
                Button("สร้างห้องใหม่") {
                    newRoomName = ""
                    showCreateSheet = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for room: ChatRoom) -> some View {
        Button {
            viewModel.selectRoom(room)
            presentationMode.wrappedValue.dismiss()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: room.id == viewModel.currentRoomID ? "checkmark.circle.fill" : "bubble.left")
                    .font(.system(size: 18))
                    .foregroundColor(room.id == viewModel.currentRoomID ? .accentColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(room.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !room.preview.isEmpty {
                        Text(room.preview)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(room.messageCount) ข้อความ • \(room.updatedText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = room
            } label: {
                Label("ลบ", systemImage: "trash")
            }

            Button {
                renameText = room.name
                renameTarget = room
            } label: {
                Label("เปลี่ยนชื่อ", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func nameSheet(title: String,
                           placeholder: String,
                           text: Binding<String>,
                           confirmTitle: String,
                           onConfirm: @escaping (String) -> Void,
                           onCancel: @escaping () -> Void) -> some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ยกเลิก", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(confirmTitle) { onConfirm(text.wrappedValue) }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
