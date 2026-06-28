import AppKit
import SwiftUI

struct AddAccountSheet: View {
    @EnvironmentObject private var model: AccountAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AddMode = .oauth
    @State private var label = ""
    @State private var callbackURL = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("", selection: $mode) {
                Text("Browser Login").tag(AddMode.oauth)
                Text("Capture Current").tag(AddMode.capture)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 20)

            VStack(alignment: .leading, spacing: 16) {
                TextField("Account name", text: $label)
                    .textFieldStyle(.roundedBorder)

                switch mode {
                case .oauth:
                    oauthPane
                case .capture:
                    capturePane
                }
            }
            .padding(20)

            Divider()
            footer
        }
        .frame(width: 520)
    }

    private var header: some View {
        HStack {
            Text("Add Account")
                .font(.headline)
            Spacer()
            Button {
                model.cancelOAuth()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.bar)
    }

    private var oauthPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let session = model.oauthSession {
                HStack {
                    TextField("Login URL", text: .constant(session.authURL.absoluteString))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.authURL.absoluteString, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    Button {
                        NSWorkspace.shared.open(session.authURL)
                    } label: {
                        Image(systemName: "safari")
                    }
                }

                TextField("Callback URL", text: $callbackURL)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel Login") {
                        model.cancelOAuth()
                    }
                    Spacer()
                    Button("Complete") {
                        Task { await model.completeOAuth(callbackURLString: callbackURL) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(callbackURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "safari")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Z.ai OAuth")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Open Login") {
                        Task { await model.startOAuth(label: label) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var capturePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Current ZCode login")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Capture") {
                    Task {
                        await model.capture(label: label)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") {
                model.cancelOAuth()
                dismiss()
            }
        }
        .padding(20)
    }
}
