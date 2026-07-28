import BandPilotKit
import SwiftUI
import UniformTypeIdentifiers

/// Add a file to the band's storage: pick, stage, PUT straight to the bucket, confirm.
///
/// Uses `.fileImporter` (the Files app) rather than `PhotosPicker`, which keeps
/// `NSPhotoLibraryUsageDescription` out of the plist and sidesteps the video-size problem entirely —
/// video is not offered here, because a 10 GB free tier holds roughly 50 videos and Backblaze caps free
/// egress at 3x stored data per day.
struct MediaUploadSheet: View {
    let bandId: Int
    let song: Song
    let vm: BandDetailViewModel
    let library: MediaLibrary

    @Environment(\.dismiss) private var dismiss
    @State private var picking = true
    @State private var staged: StagedUpload?
    @State private var name = ""
    @State private var kind: MediaFileKind = .sheet
    @State private var ownerId: Int?
    @State private var progress: Double?
    @State private var error: String?
    @State private var showRights = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                Form {
                    if let staged {
                        Section {
                            Text(staged.originalName).foregroundStyle(Palette.text)
                            Text(sizeLabel(staged.sizeBytes)).font(.caption).foregroundStyle(Palette.textDim)
                        }
                        Section("Name") {
                            TextField("Name", text: $name)
                        }
                        Section("Kind") {
                            // video deliberately absent
                            Picker("Kind", selection: $kind) {
                                Text("Lead sheet").tag(MediaFileKind.sheet)
                                Text("Audio").tag(MediaFileKind.audio)
                                Text("Image").tag(MediaFileKind.image)
                            }
                            .pickerStyle(.segmented)
                        }
                        Section("For") {
                            Picker("For", selection: $ownerId) {
                                Text("Whole band").tag(Int?.none)
                                ForEach(vm.roster) { member in
                                    Text(member.nickName).tag(Int?.some(member.id))
                                }
                            }
                            if ownerId != nil {
                                // The owner tag is a filter, not a permission. Saying so prevents the
                                // trust incident where someone tags a rough take to themselves and
                                // assumes it is private.
                                Text("Tagged for this member — still visible to the whole band.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textDim)
                            }
                        }
                        if let progress {
                            Section { ProgressView(value: progress).tint(Palette.accent) }
                        }
                        if let error {
                            Section { ErrorBanner(message: error) }
                        }
                    } else {
                        Section { Text("Choose a file…").foregroundStyle(Palette.textDim) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") { startUpload() }
                        .disabled(staged == nil || progress != nil)
                }
            }
            .fileImporter(
                isPresented: $picking,
                allowedContentTypes: [.pdf, .audio, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return dismiss() }
                    stage(url)
                case .failure:
                    dismiss()
                }
            }
            .alert("Before you share files", isPresented: $showRights) {
                Button("Cancel", role: .cancel) {}
                Button("I have the rights") { performUpload(acceptTerms: true) }
            } message: {
                Text(
                    "Only upload files your band is allowed to share — your own recordings, or material "
                        + "you hold the rights to. Scanned sheet music from a publisher usually is not. "
                        + "Files go to your band's own storage, and every band member can see them."
                )
            }
        }
        .tint(Palette.selected)
    }

    /// Copy the picked file into our own temporary area **while hashing it**.
    ///
    /// The picker's URL is a short-lived security-scoped grant: if the upload is retried minutes later
    /// that URL is dead. Staging is what makes retry possible, and the staged copy is then adopted into
    /// the cache after confirmation, so the uploader never downloads back what they just sent.
    private func stage(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("bp-upload-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: url, to: temp)
            let data = try Data(contentsOf: temp, options: .mappedIfSafe)
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            staged = StagedUpload(
                localURL: temp,
                originalName: url.lastPathComponent,
                sizeBytes: Int64(data.count),
                mimeType: mime,
                sha256: Digest.sha256Hex(of: data),
                contentMd5: Digest.md5Base64(of: data)
            )
            name = url.deletingPathExtension().lastPathComponent
            kind = Self.kind(forMime: mime)
            ownerId = vm.myBandMemberId
        } catch {
            self.error = "Could not read the selected file."
        }
    }

    private func startUpload() {
        // asked once per member, recorded server-side, so it never reappears on another device
        if vm.uploadPolicy?.requiresTermsAcceptance == true {
            showRights = true
        } else {
            performUpload(acceptTerms: false)
        }
    }

    private func performUpload(acceptTerms: Bool) {
        guard let staged else { return }
        error = nil
        progress = 0
        Task {
            // refuse locally before burning an intent, rather than learning the cap from a 403
            if let cap = vm.uploadPolicy?.maxBytes(for: kind), staged.sizeBytes > cap {
                error = "That file is \(staged.sizeBytes / 1_048_576) MB. The limit is \(cap / 1_048_576) MB."
                progress = nil
                return
            }
            do {
                let uploaded = try await MediaUploads.perform(
                    api: vm.api,
                    bandId: bandId,
                    songId: song.id,
                    staged: staged,
                    name: name.isEmpty ? staged.originalName : name,
                    kind: kind,
                    ownerBandMemberId: ownerId,
                    acceptTerms: acceptTerms
                ) { fraction in progress = fraction }

                library.adoptUploaded(uploaded, from: staged.localURL)
                vm.fileChanged(uploaded)
                dismiss()
            } catch APIError.http(let status, _, _) where status == 428 {
                // the backend insists on the confirmation before it will mint an intent
                progress = nil
                showRights = true
            } catch {
                progress = nil
                self.error = (error as? MediaTransferError)?.userMessage ?? "Upload failed — check your connection."
            }
        }
    }

    private func sizeLabel(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 0.1 ? String(format: "%.1f MB", mb) : "\(bytes / 1024) KB"
    }

    /// A photo defaults to a lead sheet, because photographing a chord chart is how bands capture them.
    static func kind(forMime mime: String) -> MediaFileKind {
        let lower = mime.lowercased()
        if lower == "application/pdf" { return .sheet }
        if lower.hasPrefix("audio/") { return .audio }
        if lower.hasPrefix("video/") { return .video }
        if lower.hasPrefix("image/") { return .sheet }
        return .image
    }
}
