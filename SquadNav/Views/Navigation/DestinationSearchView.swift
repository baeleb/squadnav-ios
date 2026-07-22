import SwiftUI
import MapKit

struct DestinationSearchView: View {
    @ObservedObject var navigationVM: NavigationViewModel
    @Environment(\.dismiss) var dismiss

    @State private var searchText = ""
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AppTheme.backgroundDark
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AppTheme.textMuted)
                    }
                    Spacer()
                    Text("Where to?")
                        .font(AppFont.fredoka(20, .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.textMuted)

                    TextField("Search for a place...", text: $searchText)
                        .font(AppFont.nunito(16))
                        .foregroundColor(AppTheme.textPrimary)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            navigationVM.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.textMuted)
                        }
                    }

                    if navigationVM.isSearching {
                        ProgressView()
                            .tint(AppTheme.primary)
                            .scaleEffect(0.8)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.backgroundInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.border, lineWidth: 1.5)
                        )
                )
                .padding(.horizontal, 20)
                .onChange(of: searchText) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if !Task.isCancelled {
                            await navigationVM.searchDestination(query: newValue)
                        }
                    }
                }

                // Results
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(navigationVM.searchResults, id: \.self) { mapItem in
                            searchResultRow(mapItem: mapItem)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
        }
    }

    private func searchResultRow(mapItem: MKMapItem) -> some View {
        Button {
            Task {
                await navigationVM.setDestinationAndCalculateRoute(mapItem)
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mapItem.name ?? "Unknown")
                        .font(AppFont.nunito(15, .bold))
                        .foregroundColor(AppTheme.textPrimary)

                    if let address = mapItem.placemark.formattedAddress {
                        Text(address)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textMuted)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.backgroundCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placemark Extension

extension CLPlacemark {
    var formattedAddress: String? {
        let components = [
            subThoroughfare,
            thoroughfare,
            locality,
            administrativeArea,
            postalCode
        ].compactMap { $0 }

        return components.isEmpty ? nil : components.joined(separator: ", ")
    }
}
