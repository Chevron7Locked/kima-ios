import SwiftUI

// MARK: - LicensesView

/// Static licenses screen — attribution for the fonts bundled in the app. App Store / distribution requires attribution for licensed fonts.
struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KimaScreenHeader(title: "licenses")
                KimaSectionHeader(title: "fonts")

                VStack(alignment: .leading, spacing: 0) {
                    licenseBlock(
                        name: "Bricolage Grotesque",
                        author: "ateliertriay/bricolage",
                        url: "https://github.com/ateliertriay/bricolage",
                        body: "Copyright 2022 The Bricolage Grotesque Project Authors. licensed under the SIL Open Font License 1.1.",
                        licenseFile: "OFL-BricolageGrotesque"
                    )
                    KimaHairline()
                    licenseBlock(
                        name: "Montserrat",
                        author: "JulietaUla/Montserrat",
                        url: "https://github.com/JulietaUla/Montserrat",
                        body: "Copyright 2011 The Montserrat Project Authors. licensed under the SIL Open Font License 1.1.",
                        licenseFile: "OFL-Montserrat"
                    )
                }
                .background(KimaColor.surface, in: RoundedRectangle(cornerRadius: KimaRadius.card))
                .padding(.horizontal, KimaSpacing.xl)

                Spacer(minLength: KimaSpacing.lg)
            }
        }
        .kimaScrollTopGround()
        .kimaMiniPlayerClearance()
        .kimaScreenCanvas()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func licenseBlock(name: String, author: String, url: String, body: String, licenseFile: String) -> some View {
        VStack(alignment: .leading, spacing: KimaSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: KimaSpacing.sm) {
                Text(name)
                    .font(KimaType.headline)
                    .foregroundStyle(KimaColor.textPrimary)
                Spacer(minLength: 0)
                Link(destination: URL(string: url)!) {
                    Text(author)
                        .font(KimaType.caption)
                        .foregroundStyle(KimaColor.textPrimary)
                        .underline()
                }
            }
            Text(body)
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                LicenseTextView(title: name, resource: licenseFile)
            } label: {
                HStack(spacing: KimaSpacing.xs) {
                    Text("view licence")
                    Image(systemName: "chevron.right")
                }
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textPrimary)
            }
        }
        .padding(KimaSpacing.lg)
    }
}

// MARK: - LicenseTextView

/// Scrolling view of a bundled licence text file, shown verbatim.
struct LicenseTextView: View {
    let title: String
    let resource: String

    private var text: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "licence text unavailable."
        }
        return contents
    }

    var body: some View {
        ZStack {
            KimaScreenGround()
            ScrollView {
                Text(text)
                    .font(KimaType.caption)
                    .foregroundStyle(KimaColor.textMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(KimaSpacing.xl)
            }
            .kimaScrollTopGround()
            .kimaMiniPlayerClearance()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
