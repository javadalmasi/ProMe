import ProMeData
import ProMeDomain
import ProMeDesignSystem
import SwiftUI

/// Personal notes: pin favorites, quick search, colored cards.
struct NotesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var notes: [NoteMO] = []
    @State private var searchText = ""
    @State private var editorPresented = false
    @State private var editingNote: NoteMO?

    var body: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "note.text",
                        title: String(localized: "No notes yet"),
                        detail: String(localized: "Write down whatever you want to keep — private and always with you.")
                    )
                    .padding(.top, 60)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(filtered, id: \.objectID) { note in
                            noteCard(note)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .padding(20)
                    .animation(.snappy(duration: 0.25), value: searchText)
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text(String(localized: "Search notes")))
        .navigationTitle(String(localized: "Notes"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorPresented = true
                } label: {
                    Label(String(localized: "New Note"), systemImage: "square.and.pencil")
                }
            }
        }
        .task(id: appModel.dataEpoch) { reload() }
        .onAppear { reload() }
        .sheet(isPresented: $editorPresented, onDismiss: reload) {
            NoteEditor()
        }
        .sheet(item: $editingNote, onDismiss: reload) { note in
            NoteEditor(note: note)
        }
    }

    private var gridColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 12)]
        #else
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
        #endif
    }

    private var filtered: [NoteMO] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText) ||
                $0.bodyText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func reload() {
        guard let services = appModel.services else { return }
        notes = (try? services.notes.all()) ?? []
    }

    @ViewBuilder
    private func noteCard(_ note: NoteMO) -> some View {
        let accent = Color.fromHex(note.colorHex ?? "") ?? .accentColor
        Button {
            editingNote = note
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let title = note.title, !title.isEmpty {
                        Text(title)
                            .font(.appHeadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.appCaption2)
                            .foregroundStyle(accent)
                    }
                }
                Text(note.bodyText)
                    .font(.appCallout)
                    .foregroundStyle(.secondary)
                    .lineLimit(6, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                Text(Format.dateText(note.updatedAt))
                    .font(.appCaption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.secondary)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.gradient)
                            .frame(height: 4)
                            .padding(.horizontal, 12)
                            .offset(y: 0)
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.isPinned ? String(localized: "Unpin") : String(localized: "Pin")) {
                note.isPinned.toggle()
                try? appModel.services?.notes.save(note)
                reload()
            }
            Button(String(localized: "Delete"), role: .destructive) {
                try? appModel.services?.notes.delete(note)
                reload()
                appModel.bumpData()
            }
        }
    }
}

/// Full-screen note editor.
struct NoteEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let note: NoteMO?

    init(note: NoteMO? = nil) {
        self.note = note
        _title = State(initialValue: note?.title ?? "")
        _bodyText = State(initialValue: note?.bodyText ?? "")
        _colorHex = State(initialValue: note?.colorHex ?? "")
        _isPinned = State(initialValue: note?.isPinned ?? false)
    }

    @State private var title: String
    @State private var bodyText: String
    @State private var colorHex: String
    @State private var isPinned: Bool

    private let palette = ["", "#F59E0B", "#10B981", "#3B82F6", "#8B5CF6", "#EC4899", "#64748B"]

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Note")) {
                    TextField(String(localized: "Title"), text: $title)
                    TextField(String(localized: "Write here…"), text: $bodyText, axis: .vertical)
                        .lineLimit(8 ... 16)
                }
                Section(String(localized: "Options")) {
                    Toggle(String(localized: "Pinned"), isOn: $isPinned)
                    Picker(String(localized: "Color"), selection: $colorHex) {
                        Text(String(localized: "Default")).tag("")
                        ForEach(palette.dropFirst(), id: \.self) { hex in
                            HStack {
                                Circle().fill(Color.fromHex(hex) ?? .accentColor).frame(width: 12, height: 12)
                                Text(hex).font(.appCaption.monospaced())
                            }
                            .tag(hex)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(note == nil ? String(localized: "New Note") : String(localized: "Edit Note"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(bodyText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 480)
        #endif
    }

    private func save() {
        guard let services = appModel.services else { return }
        if let note {
            note.title = title.isEmpty ? nil : title
            note.bodyText = bodyText
            note.colorHex = colorHex.isEmpty ? nil : colorHex
            note.isPinned = isPinned
            try? services.notes.save(note)
        } else {
            let created = try? services.notes.create(
                title: title.isEmpty ? nil : title,
                body: bodyText,
                colorHex: colorHex.isEmpty ? nil : colorHex
            )
            if isPinned, let created {
                created.isPinned = true
                try? services.notes.save(created)
            }
        }
        appModel.bumpData()
        dismiss()
    }
}
