//
//  ContentView.swift
//  Etsi-1196x2App
//
//  Dumb view: renders the view model's state and triggers actions. No logic here.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WalletValidationViewModel()

    var body: some View {
        NavigationStack {
            List {
                resultsSection
                testCertificateSection
                actionSection
            }
            .navigationTitle("EUDI Trust Lists")
        }
    }

    private var testCertificateSection: some View {
        Section("Test certificate (EUDI Ref Impl)") {
            TextEditor(text: $viewModel.pastedPEM)
                .frame(minHeight: 120)
                .font(.system(.caption, design: .monospaced))
            Picker("Context", selection: $viewModel.selectedTestContext) {
                ForEach(TestContext.allCases) { ctx in
                    Text(ctx.rawValue).tag(ctx)
                }
            }
            .pickerStyle(.segmented)
            Button {
                Task { await viewModel.runTestCertificate() }
            } label: {
                Text("Validate certificate")
            }
            .disabled(
                viewModel.phase == .loading ||
                viewModel.pastedPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch viewModel.phase {
        case .idle:
            Section {
                Text("Tap “Load trust anchors” to fetch the LoTE trust lists and resolve anchors per verification context.")
                    .foregroundStyle(.secondary)
            }
        case .loading:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading trust lists…")
                }
            }
        case .loaded:
            if !viewModel.results.isEmpty {
                Section("Trust anchors per context") {
                    ForEach(viewModel.results) { result in
                        HStack {
                            Text(result.name)
                            Spacer()
                            Text("\(result.anchorCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !viewModel.validations.isEmpty {
                Section("Validation demo") {
                    ForEach(viewModel.validations) { outcome in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: outcome.trusted ? "checkmark.seal.fill" : "xmark.seal.fill")
                                    .foregroundStyle(outcome.trusted ? .green : .red)
                                Text(outcome.label)
                            }
                            if let detail = outcome.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        case .failed(let message):
            Section("Error") {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await viewModel.run() }
            } label: {
                Text(viewModel.phase == .loading ? "Loading…" : "Load & validate (LoTE)")
            }
            .disabled(viewModel.phase == .loading)

            Button {
                Task { await viewModel.runRefImpl() }
            } label: {
                Text("Load (EUDI Ref Impl)")
            }
            .disabled(viewModel.phase == .loading)

            Button {
                Task { await viewModel.runCached() }
            } label: {
                Text("Validate (cached)")
            }
            .disabled(viewModel.phase == .loading)

            Button {
                Task { await viewModel.runBundled() }
            } label: {
                Text("Validate bundled certificate")
            }
            .disabled(viewModel.phase == .loading)
        }
    }
}

#Preview {
    ContentView()
}
