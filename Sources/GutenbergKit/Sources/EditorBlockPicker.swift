import SwiftUI

// TODO: Add search
// TODO: Group these properly
struct EditorBlockPicker: View {
    @StateObject var viewModel: EditorBlockPickerViewModel

    @State private var searchText = ""
    @State private var group = "Blocks"

    @Environment(\.dismiss) private var dismiss


    var body: some View {
        List {
            ForEach(viewModel.displayedSections) { section in
                Section(section.name) {
                    ForEach(section.blockTypes) { blockType in
                        _Label(blockType.name, systemImage: "paragraphsign")
                    }
                }
            }
        }
        .toolbar(content: {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Close", action: { dismiss() })
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu(content: {
                    Button("Blocks", action: {})
                    Button("Patterns", action: {})
                }, label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Blocks")
                            .font(.body.weight(.medium))
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary, .secondary.opacity(0.3))
                    }
                })
            }
        })
        .navigationBarTitleDisplayMode(.inline)

//        TabView(selection: $group,
//                content:  {
//            _bodyBlocks
//                .tabItem {
//                    Label("Blocks", systemImage: "batteryblock")
//                }
//                .tag("Blocks")
//            Text("Tab Content 2")
//                .tabItem {
//                    Label("Patterns", systemImage: "rectangle.3.group")
//                }
//                .tag("Patterns")
////            PhotosPicker("Media", selection: $selectedItems)
////                .photosPickerStyle(.inline)
////                .tabItem {
////                    Label("Media", systemImage: "photo.on.rectangle")
////                }
////                .tag("Media")
//        })
//        .tint(Color.primary)
    }

    @ViewBuilder
    var _bodyBlocks: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
//                SearchView(text: $searchText)
//                    .padding(.horizontal, 12)
//                    .padding(.bottom, 8)
//                 filters
//                    .padding(.horizontal)
//                    .padding(.bottom, 8)

            }
            .background(Color(uiColor: .secondarySystemBackground))


            List {
                Section("Text") {
                    _Label("Paragraph", systemImage: "paragraphsign")
                    _Label("Heading", systemImage: "bookmark")
                    _Label("List", systemImage: "list.triangle")
                    _Label("Quote", systemImage: "text.quote")
                    _Label("Table", systemImage: "tablecells")
                }
                Section("Media") {
                    _Label("Image", systemImage: "photo")
                    _Label("Gallery", systemImage: "rectangle.3.group")
                    _Label("Video", systemImage: "video")
                    _Label("Audio", systemImage: "waveform")
                }
            }
            .listStyle(.insetGrouped)
        }
//        .safeAreaInset(edge: .bottom) {
//            HStack(spacing: 30) {
//                Image(systemName: "paragraphsign")
//                Image(systemName: "bookmark")
//                Image(systemName: "photo")
//                Image(systemName: "rectangle.3.group")
//                Image(systemName: "video")
//                Image(systemName: "link")
//            }
//            .padding()
//            .background(Color.black.opacity(0.5))
//            .background(Material.thick)
//            .foregroundStyle(.white)
//            .cornerRadius(16)
//        }
//        }
//        .searchable(text: $searchText)//, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar(content: {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Close", action: { dismiss() })
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu(content: {
                    Button("Blocks", action: {})
                    Button("Patterns", action: {})
                }, label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Blocks")
                            .font(.body.weight(.medium))
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary, .secondary.opacity(0.3))
                    }
                })
            }
        })
        .navigationBarTitleDisplayMode(.inline)
//        .toolbar(.hidden, for: .navigationBar)

        .tint(Color.primary)
    }

    private var filters: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MenuItem("Blocks", isSelected: true)
                MenuItem("Patterns", isSelected: false)
//                MenuItem("Media")
                Spacer()
            }
            .font(.subheadline)
            Divider()
        }
    }
}

private struct _Label: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .frame(width: 26)
//                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
//            Image(systemName: "info.circle")
//                .foregroundColor(.secondary)
        }
    }
}

private struct MenuItem: View {
    let title: String
    let isSelected: Bool

    init(_ title: String, isSelected: Bool = false) {
        self.title = title
        self.isSelected = isSelected
    }

    var body: some View {
        VStack {
            Text(title)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            Rectangle()
                .frame(height: 2)
                .foregroundStyle(isSelected ? Color.black : Color(uiColor: .separator))
                .opacity(isSelected ? 1 : 0)
        }
    }
}

final class EditorBlockPickerViewModel: ObservableObject {
    private let sections: [EditorBlockPickerSection]
    @Published private(set) var displayedSections: [EditorBlockPickerSection] = []

    private let blockTypes: [EditorBlockType] = []

    init(blockTypes: [EditorBlockType]) {
        self.sections = Dictionary(grouping: blockTypes, by: \.category)
            .map { category, blockTypes in
                EditorBlockPickerSection(name: category ?? "–", blockTypes: blockTypes)
            }
        self.displayedSections = sections
    }
}

struct EditorBlockPickerSection: Identifiable {
    var id: String { name } // Guranteed to be unique

    let name: String
    let blockTypes: [EditorBlockType]
}
