import SwiftUI
import SwiftData

struct CloudBackupView: View {

    @Environment(CloudBackupManager.self) private var backup
    @Environment(\.modelContext) private var context
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @AppStorage("weightUnit")      private var weightUnit:      String = "kg"
    @AppStorage("heightUnit")      private var heightUnit:      String = HeightUnit.cm.rawValue
    @AppStorage("syncToHealthKit") private var syncToHealthKit: Bool   = true

    @State private var showingDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if backup.isSignedIn {
                    signedInContent
                } else {
                    signedOutContent
                }
            }
            .padding(.horizontal, DS.Space.screenGutter)
            .padding(.top, DS.Space.m)
            .padding(.bottom, 40)
        }
        .background(DS.Palette.ground.ignoresSafeArea())
        .navigationTitle("Cloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sync Error", isPresented: Binding(
            get: { backup.syncError != nil },
            set: { if !$0 { backup.syncError = nil } }
        )) {
            Button("OK") { backup.syncError = nil }
        } message: {
            Text(backup.syncError ?? "")
        }
    }

    // MARK: - Not signed in

    private var signedOutContent: some View {
        VStack(spacing: DS.Space.l) {
            // Hero
            VStack(spacing: DS.Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.indigo)
                        .frame(width: 64, height: 64)
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(spacing: DS.Space.xs) {
                    Text("Back up your data")
                        .font(DS.Typeface.title2)
                        .foregroundStyle(DS.Palette.label)
                        .multilineTextAlignment(.center)

                    Text("Your profiles, readings, and settings are backed up securely. Sign in to restore everything on a new device — no setup needed.")
                        .font(DS.Typeface.subheadline)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, DS.Space.xxl)
            .padding(.horizontal, DS.Space.m)
            .frame(maxWidth: .infinity)

            // Sign in with Google button
            Button {
                Task { await backup.signIn() }
            } label: {
                HStack(spacing: 12) {
                    GoogleGLogo(size: 22)
                    Text("Sign in with Google")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(red: 0.235, green: 0.255, blue: 0.263))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            .buttonStyle(.plain)

            Text("Your data is private and only accessible with your Google account.")
                .font(DS.Typeface.caption)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Signed in

    private var signedInContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            sectionLabel("ACCOUNT")

            VStack(spacing: 0) {
                // Account row
                HStack(spacing: DS.Space.m) {
                    AsyncImage(url: backup.userPhotoURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color.indigo)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white)
                            )
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backup.userEmail)
                            .font(DS.Typeface.body)
                            .foregroundStyle(DS.Palette.label)
                        Text("Google Account")
                            .font(DS.Typeface.caption)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                    Spacer()
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 56)

                rowDivider()

                // Last synced
                HStack {
                    Text("Last synced")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.label)
                    Spacer()
                    Text(backup.lastSyncedLabel)
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: 48)

                rowDivider()

                // Sync now
                Button {
                    Task {
                        await backup.upload(
                            profiles: profiles,
                            weightUnit: weightUnit,
                            heightUnit: heightUnit,
                            syncToHealthKit: syncToHealthKit
                        )
                    }
                } label: {
                    HStack {
                        Text(backup.isSyncing ? "Syncing…" : "Sync Now")
                            .font(DS.Typeface.body)
                            .foregroundStyle(backup.isSyncing ? DS.Palette.secondaryLabel : DS.Palette.weight)
                        Spacer()
                        if backup.isSyncing {
                            ProgressView().scaleEffect(0.85)
                        } else if backup.lastSyncedDate != nil {
                            HStack(spacing: 4) {
                                Circle().fill(DS.Palette.positive).frame(width: 8, height: 8)
                                Text("Synced")
                                    .font(DS.Typeface.caption)
                                    .foregroundStyle(DS.Palette.positive)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.l)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(backup.isSyncing)

                rowDivider()

                // Sign out
                Button { backup.signOut() } label: {
                    Text("Sign Out")
                        .font(DS.Typeface.body)
                        .foregroundStyle(DS.Palette.muscle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.l)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(DS.Palette.card,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            sectionLabel("DANGER ZONE")

            Button { showingDeleteAlert = true } label: {
                Text("Delete Cloud Backup…")
                    .font(DS.Typeface.body)
                    .foregroundStyle(DS.Palette.muscle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.l)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(DS.Palette.card,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .alert("Delete Cloud Backup?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task { await backup.deleteCloudBackup() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all your backed-up profiles and readings from the cloud. Your data on this device is not affected.")
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typeface.dateCaps)
            .tracking(0.04 * 13)
            .foregroundStyle(DS.Palette.secondaryLabel)
    }

    private func rowDivider() -> some View {
        Divider().padding(.leading, DS.Space.l)
    }
}
