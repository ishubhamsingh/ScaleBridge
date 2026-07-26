import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import SwiftData
import UIKit

@MainActor
@Observable
final class CloudBackupManager {

    // MARK: State

    var isSignedIn:     Bool   = false
    var userEmail:      String = ""
    var userPhotoURL:   URL?   = nil
    var isSyncing:      Bool   = false
    var syncError:      String? = nil
    var lastSyncedDate: Date?  = {
        let t = UserDefaults.standard.double(forKey: "cloudBackupLastSynced")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }()

    private let db = Firestore.firestore()

    /// Weigh-in IDs deleted locally but not yet removed from Firestore.
    ///
    /// Deletes can happen while signed out or offline, and `upload()` is additive —
    /// it only ever writes the records that still exist locally, so without these
    /// tombstones a deleted reading survives in the cloud and comes back on restore.
    /// Kept as explicit tombstones rather than diffing cloud against local, because a
    /// diff run before a restore (fresh install, empty local store) would read as
    /// "everything was deleted" and wipe the user's backup.
    private var pendingDeletions: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.pendingDeletionsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.pendingDeletionsKey) }
    }
    private static let pendingDeletionsKey = "cloudPendingWeighInDeletions"

    // MARK: Init

    init() {
        if let user = Auth.auth().currentUser {
            isSignedIn   = true
            userEmail    = user.email ?? ""
            userPhotoURL = user.photoURL
        }
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.isSignedIn   = user != nil
                self?.userEmail    = user?.email ?? ""
                self?.userPhotoURL = user?.photoURL
            }
        }
    }

    // MARK: Sign In

    func signIn() async {
        guard let vc = UIApplication.shared.topViewController() else {
            syncError = "Cannot present sign-in sheet."
            return
        }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: vc)
            guard let idToken = result.user.idToken?.tokenString else {
                syncError = "Sign-in failed: missing ID token."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
            userPhotoURL = result.user.profile?.imageURL(withDimension: 96)
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: Sign Out

    func signOut() {
        do {
            GIDSignIn.sharedInstance.signOut()
            try Auth.auth().signOut()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: Delete weigh-ins (local delete → Firestore)

    /// Removes deleted readings from the cloud copy.
    ///
    /// Always records the tombstones first, so a failure here (offline, signed out,
    /// permission error) is retried on the next sync instead of silently leaving the
    /// record in Firestore to be resurrected by `restore()`.
    func deleteWeighIns(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        enqueuePendingDeletions(ids.map(\.uuidString))

        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await flushPendingDeletions(userRef: db.collection("users").document(uid))
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func enqueuePendingDeletions(_ idStrings: [String]) {
        var queue = pendingDeletions
        for id in idStrings where !queue.contains(id) { queue.append(id) }
        pendingDeletions = queue
    }

    /// Deletes queued documents one at a time, persisting progress so a mid-way
    /// failure doesn't lose the remaining tombstones. Firestore deletes are
    /// idempotent, so re-running is safe.
    private func flushPendingDeletions(userRef: DocumentReference) async throws {
        var remaining = pendingDeletions
        guard !remaining.isEmpty else { return }

        for idStr in pendingDeletions {
            try await userRef.collection("weigh_ins").document(idStr).delete()
            remaining.removeAll { $0 == idStr }
            pendingDeletions = remaining
        }
    }

    // MARK: Upload (local → Firestore)

    func upload(profiles: [UserProfile], weightUnit: String, heightUnit: String, syncToHealthKit: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let userRef = db.collection("users").document(uid)

            // Clear anything deleted while offline or signed out before re-uploading,
            // otherwise those records linger in the cloud.
            try await flushPendingDeletions(userRef: userRef)

            try await userRef.collection("settings").document("app").setData([
                "weightUnit": weightUnit,
                "heightUnit": heightUnit,
                "syncToHealthKit": syncToHealthKit
            ])

            for profile in profiles {
                var pData: [String: Any] = [
                    "id":          profile.id.uuidString,
                    "name":        profile.name,
                    "isMale":      profile.isMale,
                    "dateOfBirth": profile.dateOfBirth.timeIntervalSince1970,
                    "heightCm":    Double(profile.heightCm),
                    "isPrimary":   profile.isPrimary,
                    "avatar":      profile.avatar,
                    "createdAt":   profile.createdAt.timeIntervalSince1970
                ]
                if let g = profile.goalWeightKg      { pData["goalWeightKg"]       = Double(g) }
                if let g = profile.goalBodyFatPercent { pData["goalBodyFatPercent"] = Double(g) }

                try await userRef.collection("profiles")
                    .document(profile.id.uuidString)
                    .setData(pData)

                for w in profile.weighIns {
                    var wData: [String: Any] = [
                        "id":                w.id.uuidString,
                        "profileId":         profile.id.uuidString,
                        "date":              w.date.timeIntervalSince1970,
                        "weightKg":          Double(w.weightKg),
                        "impedance":         Double(w.impedance),
                        "syncedToHealthKit": w.syncedToHealthKit
                    ]
                    if let v = w.fatPercent    { wData["fatPercent"]    = Double(v) }
                    if let v = w.waterPercent  { wData["waterPercent"]  = Double(v) }
                    if let v = w.musclePercent { wData["musclePercent"] = Double(v) }
                    if let v = w.bonePercent   { wData["bonePercent"]   = Double(v) }
                    if let v = w.bmi           { wData["bmi"]           = Double(v) }

                    try await userRef.collection("weigh_ins")
                        .document(w.id.uuidString)
                        .setData(wData)
                }
            }

            recordSyncTime()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: Restore (Firestore → local SwiftData)

    func restore(into context: ModelContext) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw BackupError.notSignedIn }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        let userRef = db.collection("users").document(uid)

        // Restore is a merge, not an import: reuse what's already here and skip
        // anything we already have, so restoring onto a device with existing data
        // doesn't duplicate every profile and reading.
        let existingProfiles  = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let existingWeighInIDs = Set(((try? context.fetch(FetchDescriptor<WeighIn>())) ?? []).map(\.id))
        let tombstoned = Set(pendingDeletions)

        // Profiles
        let profilesSnap = try await userRef.collection("profiles").getDocuments()
        var profileMap: [String: UserProfile] = [:]
        for p in existingProfiles { profileMap[p.id.uuidString] = p }

        for doc in profilesSnap.documents {
            let d = doc.data()
            guard
                let idStr     = d["id"]          as? String, let id = UUID(uuidString: idStr),
                let name      = d["name"]         as? String,
                let isMale    = d["isMale"]       as? Bool,
                let dobT      = d["dateOfBirth"]  as? Double,
                let heightCm  = d["heightCm"]     as? Double,
                let isPrimary = d["isPrimary"]    as? Bool,
                let avatar    = d["avatar"]       as? String,
                let createdT  = d["createdAt"]    as? Double
            else { continue }

            // Already present locally — keep the local copy, don't insert a duplicate.
            if profileMap[idStr] != nil { continue }

            let profile = UserProfile(
                name: name, isMale: isMale,
                dateOfBirth: Date(timeIntervalSince1970: dobT),
                heightCm: Float(heightCm), isPrimary: isPrimary, avatar: avatar
            )
            profile.id        = id
            profile.createdAt = Date(timeIntervalSince1970: createdT)
            profile.goalWeightKg       = (d["goalWeightKg"]       as? Double).map(Float.init)
            profile.goalBodyFatPercent = (d["goalBodyFatPercent"] as? Double).map(Float.init)
            context.insert(profile)
            profileMap[idStr] = profile
        }

        // Weigh-ins
        let weighInsSnap = try await userRef.collection("weigh_ins").getDocuments()
        for doc in weighInsSnap.documents {
            let d = doc.data()
            guard
                let idStr       = d["id"]        as? String, let id = UUID(uuidString: idStr),
                let profileIdStr = d["profileId"] as? String,
                let profile     = profileMap[profileIdStr],
                let dateT       = d["date"]       as? Double,
                let weightKg    = d["weightKg"]   as? Double,
                let impedance   = d["impedance"]  as? Double
            else { continue }

            // Skip records we already hold, and any the user deleted locally while
            // the cloud copy hadn't caught up yet — restoring must not resurrect them.
            if existingWeighInIDs.contains(id) || tombstoned.contains(idStr) { continue }

            let w = WeighIn(
                restoring: id,
                date: Date(timeIntervalSince1970: dateT),
                weightKg: Float(weightKg),
                impedance: Float(impedance),
                fatPercent:    (d["fatPercent"]    as? Double).map(Float.init),
                waterPercent:  (d["waterPercent"]  as? Double).map(Float.init),
                musclePercent: (d["musclePercent"] as? Double).map(Float.init),
                bonePercent:   (d["bonePercent"]   as? Double).map(Float.init),
                bmi:           (d["bmi"]           as? Double).map(Float.init),
                syncedToHealthKit: d["syncedToHealthKit"] as? Bool ?? false,
                user: profile
            )
            context.insert(w)
        }

        try context.save()
        recordSyncTime()
    }

    // MARK: Delete cloud backup

    func deleteCloudBackup() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let userRef = db.collection("users").document(uid)
            for collection in ["profiles", "weigh_ins", "settings"] {
                let snap = try await userRef.collection(collection).getDocuments()
                for doc in snap.documents {
                    try await doc.reference.delete()
                }
            }
            lastSyncedDate = nil
            UserDefaults.standard.removeObject(forKey: "cloudBackupLastSynced")
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: Formatted last sync label

    var lastSyncedLabel: String {
        guard let d = lastSyncedDate else { return "Never" }
        let cal = Calendar.current
        if cal.isDateInToday(d)     { return "Today at \(d.formatted(.dateTime.hour().minute()))" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Private helpers

    private func recordSyncTime() {
        let now = Date()
        lastSyncedDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "cloudBackupLastSynced")
    }
}

// MARK: - Error

enum BackupError: LocalizedError {
    case notSignedIn
    var errorDescription: String? { "Not signed in to cloud backup." }
}

// MARK: - UIApplication helper

private extension UIApplication {
    func topViewController() -> UIViewController? {
        guard
            let scene = connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root  = scene.keyWindow?.rootViewController
        else { return nil }
        return topVC(from: root)
    }

    private func topVC(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController         { return topVC(from: presented) }
        if let nav = vc as? UINavigationController,
           let top = nav.topViewController                    { return topVC(from: top) }
        if let tab = vc as? UITabBarController,
           let sel = tab.selectedViewController               { return topVC(from: sel) }
        return vc
    }
}
