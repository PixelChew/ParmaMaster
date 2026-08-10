import SwiftUI

struct SortMenu: View {
    @Binding var field: EntrySortField
    @Binding var direction: SortDirection

    var body: some View {
        Menu {
            Section("Sort by") {
                Picker("Sort by", selection: $field) {
                    ForEach(EntrySortField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
            }
            Section("Direction") {
                Picker("Direction", selection: $direction) {
                    ForEach(SortDirection.allCases) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }
            }
        } label: {
            Label("Sort entries", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Sort entries")
    }
}
