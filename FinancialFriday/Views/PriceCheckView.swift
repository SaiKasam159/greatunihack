import PhotosUI
import SwiftUI
import UIKit

/// Workflow 1 (Product Image Price Finder): photo in, price comparison out.
struct PriceCheckView: View {
    @State private var viewModel = PriceCheckViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var base64: String?
    @State private var isPreparing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                photoCard

                HStack(spacing: 10) {
                    Text("Country").font(.system(size: 14)).foregroundStyle(GU.secondary)
                    TextField("uk", text: $viewModel.country)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(width: 80)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(GU.surface, in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                }

                Button {
                    guard let base64 else { return }
                    Task { await viewModel.search(base64Image: base64) }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSearching { ProgressView().tint(.white) }
                        Text(viewModel.isSearching ? "Comparing prices..." : "Compare prices")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(canSearch ? GU.blue : GU.border, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(canSearch ? .white : GU.secondary)
                }
                .disabled(!canSearch)

                results
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(.white)
        .navigationTitle("Price check")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await prepare(item) }
        }
    }

    private var canSearch: Bool { base64 != nil && !viewModel.isSearching }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRODUCT IMAGE PRICE FINDER").eyebrow()
            Text("Is it a good price?").font(.system(size: 22, weight: .semibold))
            Text("Photograph the product or the tag. We read the brand and model, then compare the exact item and close alternatives.")
                .font(.system(size: 14))
                .foregroundStyle(GU.secondary)
        }
    }

    private var photoCard: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Group {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipped()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 30))
                            .foregroundStyle(GU.blue)
                        Text(isPreparing ? "Preparing photo..." : "Add a product photo")
                            .font(.system(size: 14, weight: .semibold))
                        Text("JPEG or PNG, up to 4 MB")
                            .font(.caption)
                            .foregroundStyle(GU.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                }
            }
            .background(GU.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(preview == nil ? GU.border : .clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var results: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Searching Google Shopping...").font(.system(size: 14)).foregroundStyle(GU.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Price finder unavailable", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GU.orange)
                Text(message).font(.caption).foregroundStyle(GU.secondary)
                HStack(spacing: 10) {
                    if let base64 {
                        Button("Try again") { Task { await viewModel.search(base64Image: base64) } }
                            .buttonStyle(.bordered)
                    }
                    Button("Show sample result") { viewModel.showSample() }
                        .buttonStyle(.borderedProminent)
                        .tint(GU.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(red: 1, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 14))
        case .loaded(let result):
            loadedResult(result)
        }
    }

    @ViewBuilder
    private func loadedResult(_ result: PriceFinderResult) -> some View {
        if result.isDemo {
            Label("Sample data - n8n not reachable", systemImage: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GU.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 0.96, blue: 0.93), in: RoundedRectangle(cornerRadius: 12))
        }
        if let product = result.product, !product.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("MATCHED PRODUCT").eyebrow()
                Text(product).font(.system(size: 16, weight: .semibold))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GU.paleBlue, in: RoundedRectangle(cornerRadius: 14))
        }
        ForEach([PriceMatchKind.exact, .sameBrand, .similar], id: \.rawValue) { kind in
            let matches = result.matches.filter { $0.kind == kind }
            if !matches.isEmpty {
                Text(kind.label.uppercased()).eyebrow().padding(.top, 4)
                ForEach(matches) { match in
                    priceRow(match)
                }
            }
        }
        if result.matches.isEmpty {
            ContentUnavailableView(
                "No matches found",
                systemImage: "magnifyingglass",
                description: Text("Try a clearer photo with the brand and model visible.")
            )
        }
    }

    private func priceRow(_ match: PriceMatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.title.isEmpty ? match.model : match.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(match.shop)
                        .font(.caption)
                        .foregroundStyle(GU.secondary)
                }
                Spacer()
                Text(AppFormatting.currency(Decimal(match.price)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(match.kind == .exact ? GU.green : GU.ink)
            }
            if !match.notes.isEmpty {
                Text(match.notes).font(.caption).foregroundStyle(GU.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let link = match.link {
                Link(destination: link) {
                    Label("Open shop", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(GU.blue)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GU.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func prepare(_ item: PhotosPickerItem) async {
        isPreparing = true
        defer { isPreparing = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let compressed = image.downscaled(maxDimension: 1600)
        preview = compressed
        base64 = compressed.jpegData(compressionQuality: 0.8)?.base64EncodedString()
        viewModel.reset()
    }
}

private extension UIImage {
    /// Keeps photos well under the workflow's 4 MB guard without visible quality loss.
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
